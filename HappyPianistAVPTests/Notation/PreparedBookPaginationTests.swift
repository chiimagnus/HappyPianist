import AVFAudio
import Foundation
import Library
import MusicXML
@testable import Notation
import Practice
import SwiftUI
import Testing
import UIKit
@testable import HappyPianistAVP

@Test
@MainActor
func preparedPracticeInstallsFullBookAndManualNavigationReachesLastSpread() async throws {
    let prepared = try await preparedBookFixture()
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper())
    defer { session.shutdown() }
    installBook(prepared, into: session)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    #expect(plan.pages.flatMap(\.measures).map(\.span) == prepared.measureSpans)
    #expect(plan.spreadCount > 1)
    #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 0)
    session.startGuidingIfReady()
    session.skip()
    let lastStep = try #require(prepared.steps.last)
    #expect(session.notationNavigationTick() == lastStep.tick)
    #expect(plan.spreadIndex(containingTick: lastStep.tick) == plan.spreadCount - 1)
    session.skip()
    #expect(session.state == .completed)
    #expect(session.notationNavigationTick() == lastStep.tick)
    await owner.load(try bookInput(session))
    #expect(owner.buildCount == 1)
    session.clearPreparedSong()
    #expect(session.notationNavigationTick() == nil)
    #expect(session.notationScoreFacts == nil)
    owner.clear()
    #expect(owner.plan == nil)
}

@Test
@MainActor
func preparedAutoplayRestBoundariesDriveBookInsteadOfStaleGuideAndPauseHolds() async throws {
    let prepared = try await preparedBookFixture()
    let playback = BookTransportTestPlayback()
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper(), sequencerPlaybackService: playback)
    defer { session.shutdown() }
    installBook(prepared, into: session)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    let destination = try #require(plan.pages.first { $0.index >= 2 }?.measures.first?.span)
    var turn = GrandStaffNotationPageTurnState()
    let initialTick = try #require(session.notationNavigationTick())
    turn.request(identity: plan.turnIdentity, target: try #require(plan.spreadIndex(containingTick: initialTick)), animated: true)
    session.setAutoplayEnabled(true)
    session.startGuidingIfReady()
    await TestAsyncWait.until("prepared autoplay started") {
        if case .transport = session.pianoDemonstrationHandsTiming() {
            return playback.sequence != nil
        }
        return false
    }
    let baseSeconds = session.tempoMap.timeSeconds(atTick: prepared.steps[0].tick)
    playback.seconds = session.tempoMap.timeSeconds(atTick: destination.startTick) - baseSeconds + session.autoplayTimingLeadInSeconds + 0.001
    await TestAsyncWait.until("rest boundary reached actual spread") { session.notationNavigationTick() == destination.startTick }
    #expect(session.currentStepIndex == 0)
    #expect(session.currentPianoHighlightGuide?.tick != destination.startTick)
    #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 1)
    turn.request(identity: plan.turnIdentity, target: 1, animated: true)
    let forward = try #require(turn.transition)
    #expect(forward.isForward)
    playback.holdNextSeconds = true
    await TestAsyncWait.until("in-flight transport sample") { playback.pendingSeconds != nil }
    playback.seconds = session.tempoMap.timeSeconds(atTick: destination.endTick) - baseSeconds + session.autoplayTimingLeadInSeconds + 0.001
    await session.pauseAutoplayPlayback()
    let held = session.notationNavigationTick()
    playback.releasePendingSeconds()
    try await Task.sleep(for: .milliseconds(100))
    #expect(session.notationNavigationTick() == held)
    let heldTick = try #require(session.notationNavigationTick())
    turn.request(identity: plan.turnIdentity, target: try #require(plan.spreadIndex(containingTick: heldTick)), animated: true)
    #expect(turn.transition == forward)
    try await session.resumeAutoplayPlayback()
    await TestAsyncWait.until("resumed transport position") { session.notationNavigationTick() != held }
    session.setAutoplayEnabled(false)
    #expect(session.stateStore.notationPositionTick == nil)
    #expect(session.notationNavigationTick() == session.currentStep?.tick)
}

@Test(arguments: [ManualAdvanceMode.step, .measure])
@MainActor
func preparedBookPassageRetryInvalidationAndReplacementKeepFullPagination(mode: ManualAdvanceMode) async throws {
    let prepared = try await preparedBookFixture()
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper())
    defer { session.shutdown() }
    installBook(prepared, into: session)
    session.stateStore.activeManualAdvanceMode = mode
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let original = try #require(owner.plan)
    session.startGuidingIfReady()
    session.skip()
    #expect(original.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == original.spreadCount - 1)
    let spans = prepared.measureSpans
    for boundaries in [(0, 30), (96, 127), (0, 127)] {
        session.roundConfigurationController.pendingPassage = try #require(PracticePassage(start: spans[boundaries.0].occurrenceID, end: spans[boundaries.1].occurrenceID))
        _ = session.applyPendingRoundConfiguration()
        #expect(session.activeNotationOverlay.activeTickRange == spans[boundaries.0].startTick..<spans[boundaries.1].endTick)
        #expect(session.measureSpans == spans)
        #expect(original.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == (boundaries.0 == 96 ? original.spreadCount - 1 : 0))
        await owner.load(try bookInput(session))
        #expect(owner.plan == original)
        #expect(owner.buildCount == 1)
    }
    session.retryMeasure(spans[0].sourceMeasureID)
    #expect(original.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 0)
    session.skip()
    #expect(session.state == .completed)
    #expect(session.notationNavigationTick() == prepared.steps[0].tick)
    let missing = PracticeMeasureOccurrenceID(sourceMeasureID: .init(partID: "missing", sourceMeasureIndex: 0, sourceNumberToken: "1"), occurrenceIndex: 0)
    session.roundConfigurationController.pendingPassage = try #require(PracticePassage(start: missing, end: missing))
    _ = session.applyPendingRoundConfiguration()
    #expect(session.stateStore.isActiveRangeInvalid)
    #expect(session.notationNavigationTick() == nil)
    #expect(session.activeNotationOverlay == .empty)
    session.resetSession()
    #expect(session.notationProjection == nil && session.notationScoreFacts == nil)
    #expect(session.notationNavigationTick() == nil)
    owner.clear()
    let replacement = try await preparedBookFixture()
    installBook(replacement, into: session)
    await owner.load(try bookInput(session))
    #expect(owner.plan?.input.identity == replacement.identity)
    #expect(owner.plan?.pages.map(\.id) == original.pages.map(\.id))
    #expect(owner.buildCount == 2)
}

@Test(arguments: ["saved", "failed", "cancelled"])
@MainActor
func preparedBookResumeAndReturnPreserveNavigationAndActualProgress(outcome: String) async throws {
    let prepared = try await preparedBookFixture()
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = PracticeProgressPaths(rootDirectoryURL: directory)
    let repository = FilePracticeProgressRepository(paths: paths)
    let configuration = PracticeRoundConfiguration(passage: try #require(PracticePassage(start: prepared.measureSpans[0].occurrenceID, end: prepared.measureSpans[127].occurrenceID)), handMode: .both, tempoScale: 0.8, loopEnabled: false, requiredSuccesses: 2)
    let progress = SongPracticeProgress(identity: prepared.identity, activeConfiguration: configuration, resumePoint: .init(occurrenceID: prepared.measureSpans[127].occurrenceID, stepIndex: 1, updatedAt: .now), updatedAt: .now)
    try await repository.upsert(progress)
    let sessionRepository = outcome == "failed" ? FilePracticeProgressRepository(paths: paths, writeDocument: { _, _ in throw CocoaError(.fileWriteOutOfSpace) }) : repository
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper(), progressCoordinator: PracticeProgressCoordinator(repository: sessionRepository, checkpointDelay: .seconds(60)))
    defer { session.shutdown() }
    installBook(prepared, into: session)
    await session.applyLaunchRestorePolicy(.exactAvailable)
    #expect(session.state == .ready && session.isRestoredSessionPaused)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == plan.spreadCount - 1)
    session.startGuidingIfReady()
    #expect(session.currentStepIndex == 1)
    var restoredTurn = GrandStaffNotationPageTurnState()
    restoredTurn.request(identity: plan.turnIdentity, target: plan.spreadCount - 1, animated: true)
    #expect(restoredTurn.target == plan.spreadCount - 1 && restoredTurn.transition == nil)
    session.navigateNotation(to: prepared.steps[0].tick, identity: prepared.identity)
    #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 0)
    if outcome == "cancelled" {
        #expect(await session.suspendAndFlushProgress() == .saved)
        session.resumeAfterSuspension()
        #expect(session.state == .ready && session.isRestoredSessionPaused && !session.hasShutdown)
    } else {
        let result = await session.flushAndShutdown()
        if outcome == "failed" {
            if case .failed = result {} else { Issue.record("Expected actual persistence failure") }
            #expect(session.state == .ready && !session.hasShutdown)
            #expect(session.songIdentity == prepared.identity)
        } else {
            #expect(result == .saved && session.hasShutdown)
        }
    }
    #expect(session.sessionProgress?.measureFacts == progress.measureFacts)
    #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 0)
    await owner.load(try bookInput(session))
    #expect(owner.plan == plan && owner.buildCount == 1)
    let persisted = try #require(await repository.progress(for: prepared.identity))
    #expect(persisted.resumePoint?.stepIndex == (outcome == "failed" ? 1 : 0))
    #expect(persisted.measureFacts == progress.measureFacts)
}

@Test
@MainActor
func nativeSequencePreservesSilentTailForTransportPositionEvents() async throws {
    let prepared = try await preparedBookFixture()
    let tempoMap = MusicXMLTempoMap(performanceEvents: prepared.performancePlan.tempoEvents)
    let end = try #require(prepared.measureSpans.dropLast().last?.endTick)
    let timeline = AutoplayPerformanceTimeline.build(plan: prepared.performancePlan, guideProjection: prepared.highlightGuides.filter { $0.tick < end }, stepProjection: prepared.steps.filter { $0.tick < end }, tempoMap: tempoMap, practiceHandMode: .both, measureBoundaryTicks: prepared.measureSpans.map(\.startTick).filter { $0 <= end })
    let expected = tempoMap.timeSeconds(atTick: end)
    let sequence = try await PlaybackSequenceBuilder().buildPerformanceSequence(timeline: timeline, tempoMap: tempoMap, startTick: 0, endTick: end, leadInSeconds: 0)
    #expect(sequence.durationSeconds >= expected)
    let sequencer = AVAudioSequencer()
    try sequencer.load(from: sequence.midiData, options: [])
    #expect((sequencer.tracks.map(\.lengthInSeconds).max() ?? 0) >= expected - 0.00001)
    let schedule = AutoplayTimelineTimeSchedule(timeline: timeline, tickToSeconds: { tempoMap.timeSeconds(atTick: $0) }, startTick: 0)
    var cursor = AutoplayTimelineTimeCursor(schedule: schedule)
    let emitted = cursor.advance(toSeconds: expected)
    #expect(emitted.last?.tick == end)
    #expect(emitted.last?.event == .position)
    #expect(cursor.isFinished)
}

@MainActor
private func preparedBookFixture(dense: Bool = false) async throws -> PreparedPractice {
    let measures = (1...128).map { index in
        let content = index == 1 || index == 128 ? "<pitch><step>C</step><octave>5</octave></pitch>" : "<rest measure=\"yes\"/>"
        let notes = dense ? (0..<4).map { note in "<note><pitch><step>\(note.isMultiple(of: 2) ? "C" : "G")</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type><staff>1</staff></note>" }.joined() : "<note>\(content)<duration>4</duration><type>whole</type><staff>1</staff></note>"
        return "<measure number=\"\(index)\">\(index == 1 ? "<attributes><divisions>1</divisions><staves>2</staves><time><beats>4</beats><beat-type>4</beat-type></time></attributes>" : "")\(notes)</measure>"
    }.joined()
    let xml = "<score-partwise><part-list><score-part id=\"P1\"><part-name>Piano</part-name></score-part></part-list><part id=\"P1\">\(measures)</part></score-partwise>"
    let url = URL.temporaryDirectory.appending(path: "book-\(UUID()).musicxml")
    try Data(xml.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try await PracticePreparationService(diagnosticsReporter: InMemoryDiagnosticsReporter()).prepare(songID: UUID(), from: url, file: ImportedMusicXMLFile(fileName: url.lastPathComponent, storedURL: url, importedAt: .distantPast), options: .practice)
}

@Test
@MainActor
func preparedNavigationFeedsSingleTurnStateAcrossRetryJumpAndScoreReplacement() async throws {
    let prepared = try await preparedBookFixture(dense: true)
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper())
    defer { session.shutdown() }
    installBook(prepared, into: session)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    #expect(plan.spreadCount > 3)
    var turn = GrandStaffNotationPageTurnState()
    func target() throws -> Int {
        let tick = try #require(session.notationNavigationTick())
        return try #require(plan.spreadIndex(containingTick: tick))
    }
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    let initial = turn
    session.startGuidingIfReady()
    session.skip()
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    #expect(turn == initial)
    let firstNextStep = try #require(prepared.steps.firstIndex { plan.spreadIndex(containingTick: $0.tick) == 1 })
    session.moveToStep(firstNextStep, shouldPlaySound: false)
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    let forward = try #require(turn.transition)
    #expect(forward.source == 0 && forward.target == 1 && forward.isForward)
    session.skip()
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    #expect(turn.transition == forward)
    turn.complete(forward)
    session.retryMeasure(prepared.measureSpans[0].sourceMeasureID)
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    let backward = try #require(turn.transition)
    #expect(!backward.isForward && backward.target == 0)
    turn.complete(backward)
    session.roundConfigurationController.pendingPassage = try #require(PracticePassage(start: prepared.measureSpans[0].occurrenceID, end: prepared.measureSpans[127].occurrenceID))
    _ = session.applyPendingRoundConfiguration()
    session.startGuidingIfReady()
    session.moveToStep(prepared.steps.count - 1, shouldPlaySound: false)
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    #expect(turn.target == plan.spreadCount - 1 && turn.transition == nil)
    session.moveToStep(0, shouldPlaySound: false)
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    #expect(turn.transition == nil)
    session.moveToStep(firstNextStep, shouldPlaySound: false)
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    let superseded = try #require(turn.transition)
    let laterStep = try #require(prepared.steps.firstIndex { plan.spreadIndex(containingTick: $0.tick) == 2 })
    session.moveToStep(laterStep, shouldPlaySound: false)
    turn.request(identity: plan.turnIdentity, target: try target(), animated: true)
    turn.complete(superseded)
    #expect(turn.target == 2 && turn.transition == nil)
    await owner.load(try bookInput(session))
    let originalPlanUnchanged = owner.plan == plan
    #expect(owner.buildCount == 1 && originalPlanUnchanged)
    session.resetSession()
    turn.clear()
    #expect(session.notationNavigationTick() == nil)
    let replacement = try await preparedBookFixture(dense: true)
    installBook(replacement, into: session)
    await owner.load(try bookInput(session))
    let newPlan = try #require(owner.plan)
    #expect(newPlan.pages.map(\.id) == plan.pages.map(\.id))
    let replacementTick = try #require(session.notationNavigationTick())
    turn.request(identity: newPlan.turnIdentity, target: try #require(newPlan.spreadIndex(containingTick: replacementTick)), animated: true)
    turn.complete(superseded)
    #expect(turn.identity == newPlan.turnIdentity && turn.target == 0 && turn.transition == nil)
    #expect(owner.buildCount == 2)
}

@Test(arguments: [false, true])
@MainActor
func manualBookNavigationMovesPracticePositionWithoutInventingMeasureResults(dense: Bool) async throws {
    let prepared = try await preparedBookFixture(dense: dense)
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper())
    defer { session.shutdown() }
    installBook(prepared, into: session)
    await session.applyLaunchRestorePolicy(.freshDefaults)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    let tick = try #require(plan.navigationTick(forSpread: 1))
    let before = session.sessionProgress?.measureFacts
    session.navigateNotation(to: tick, identity: prepared.identity)
    #expect(session.notationNavigationTick() == tick)
    #expect(plan.spreadIndex(containingTick: tick) == 1)
    #expect(session.steps[session.currentStepIndex].tick >= tick)
    #expect(session.sessionProgress?.measureFacts == before)
    #expect(session.state != .completed)
    if !dense {
        #expect(session.state == .ready && session.isRestoredSessionPaused)
        #expect(session.currentPianoHighlightGuide == nil)
    }
    session.navigateNotation(to: prepared.steps[0].tick, identity: prepared.identity)
    #expect(session.currentStepIndex == 0)
    #expect(session.notationNavigationTick() == prepared.steps[0].tick)
    session.startGuidingIfReady()
    session.skip()
    #expect(session.notationNavigationTick() == session.currentStep?.tick)
    #expect(session.stateStore.notationPositionTick == nil)
    await owner.load(try bookInput(session))
    #expect(owner.buildCount == 1)
}

@Test
@MainActor
func manualBookNavigationRejectsOldSongAndPagesOutsideActivePassage() async throws {
    let prepared = try await preparedBookFixture(dense: true)
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper())
    defer { session.shutdown() }
    installBook(prepared, into: session)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    let span = try #require(plan.pages[2].measures.first?.span)
    session.roundConfigurationController.pendingPassage = try #require(PracticePassage(start: span.occurrenceID, end: span.occurrenceID))
    _ = session.applyPendingRoundConfiguration()
    let range = try #require(session.activeRange?.tickRange)
    #expect(plan.navigationTick(forSpread: 0, within: range) == nil)
    #expect(plan.navigationTick(forSpread: 1, within: range) == span.startTick)
    #expect(plan.navigationTick(forSpread: -1) == nil)
    #expect(plan.navigationTick(forSpread: plan.spreadCount) == nil)
    let step = session.currentStepIndex
    session.navigateNotation(to: 0, identity: prepared.identity)
    #expect(session.currentStepIndex == step && session.state == .ready)
    let another = try await preparedBookFixture(dense: true)
    session.navigateNotation(to: span.startTick, identity: another.identity)
    #expect(session.currentStepIndex == step && session.state == .ready)
    session.navigateNotation(to: span.startTick, identity: prepared.identity)
    #expect(session.notationNavigationTick() == span.startTick)
    session.clearPreparedSong()
    session.navigateNotation(to: span.startTick, identity: prepared.identity)
    #expect(session.notationNavigationTick() == nil && session.state == .idle)
}

@Test
@MainActor
func manualBookTurnSeeksActualTransportAndPreservesExplicitPause() async throws {
    let prepared = try await preparedBookFixture()
    let playback = BookTransportTestPlayback()
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper(), sequencerPlaybackService: playback)
    defer { session.shutdown() }
    installBook(prepared, into: session)
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(try bookInput(session))
    let plan = try #require(owner.plan)
    let tick = try #require(plan.navigationTick(forSpread: 1))
    session.setAutoplayEnabled(true)
    session.startGuidingIfReady()
    await TestAsyncWait.until("transport loaded before manual turn") { playback.loadCount == 1 }
    playback.holdNextSeconds = true
    await TestAsyncWait.until("old transport poll held") { playback.pendingSeconds != nil }
    session.navigateNotation(to: tick, identity: prepared.identity)
    #expect(session.notationNavigationTick() == tick)
    playback.seconds = 0
    playback.releasePendingSeconds()
    await TestAsyncWait.until("manual turn loaded replacement transport") { playback.loadCount == 2 }
    #expect(session.notationNavigationTick() == tick)
    let nextSpan = try #require(plan.pages[2].measures.dropFirst().first?.span)
    playback.seconds = session.tempoMap.timeSeconds(atTick: nextSpan.startTick) - session.tempoMap.timeSeconds(atTick: tick) + session.autoplayTimingLeadInSeconds + 0.001
    await TestAsyncWait.until("replacement transport follows turned page") { session.notationNavigationTick() == nextSpan.startTick }
    await session.pauseAutoplayPlayback()
    session.navigateNotation(to: 0, identity: prepared.identity)
    #expect(session.notationNavigationTick() == 0 && session.state == .ready)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playback.loadCount == 2)
    playback.seconds = 0
    try await session.resumeAutoplayPlayback()
    await TestAsyncWait.until("explicit resume after paused page turn") { playback.loadCount == 3 }
    #expect(session.notationNavigationTick() == 0)
}

@Test
@MainActor
func replacedBookTransportRejectsLateFailureFromCancelledGeneration() async throws {
    let prepared = try await preparedBookFixture()
    let builder = DelayedFailingBookSequenceBuilder()
    let playback = BookTransportTestPlayback()
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper(), sequencerPlaybackService: playback, playbackSequenceBuilder: builder)
    defer { session.shutdown() }
    installBook(prepared, into: session)
    session.setAutoplayEnabled(true)
    session.startGuidingIfReady()
    await TestAsyncWait.until("first generation held during build") { await builder.hasPendingFirstBuild() }
    session.skip()
    let destination = try #require(prepared.steps.last?.tick)
    await TestAsyncWait.until("replacement generation actually playing") { playback.sequence != nil && session.stateStore.notationPositionTick == destination }
    await builder.failFirstBuild()
    try await Task.sleep(for: .milliseconds(100))
    #expect(session.autoplayState == .playing)
    #expect(session.autoplayErrorMessage == nil)
    #expect(session.stateStore.notationPositionTick == destination)
    #expect(session.notationNavigationTick() == destination)
}

private actor DelayedFailingBookSequenceBuilder: PlaybackSequenceBuildingProtocol {
    enum Failure: Error { case replacedBuild }
    private var requestCount = 0
    private var firstBuild: CheckedContinuation<PracticeSequencerSequence, Error>?

    func buildPerformanceSequence(timeline: AutoplayPerformanceTimeline, tempoMap: MusicXMLTempoMap, startTick: Int, endTick: Int?, leadInSeconds: TimeInterval) async throws -> PracticeSequencerSequence {
        requestCount += 1
        if requestCount == 1 {
            return try await withCheckedThrowingContinuation { firstBuild = $0 }
        }
        return try await PlaybackSequenceBuilder().buildPerformanceSequence(timeline: timeline, tempoMap: tempoMap, startTick: startTick, endTick: endTick, leadInSeconds: leadInSeconds)
    }

    func hasPendingFirstBuild() -> Bool { firstBuild != nil }
    func failFirstBuild() {
        firstBuild?.resume(throwing: Failure.replacedBuild)
        firstBuild = nil
    }
}

@MainActor
private func installBook(_ prepared: PreparedPractice, into session: PracticeSessionViewModel) {
    session.installPreparedSteps(prepared.steps, identity: prepared.identity, performancePlan: prepared.performancePlan, notationProjection: prepared.notationProjection, notationScoreFacts: PracticeNotationScoreFacts(logicalInstrument: prepared.scoreContext.logicalInstrument, structuralPartID: prepared.scoreContext.structuralPartID), attributeTimeline: prepared.attributeTimeline, highlightGuides: prepared.highlightGuides, measureSpans: prepared.measureSpans)
}

@MainActor
private func bookInput(_ session: PracticeSessionViewModel) throws -> GrandStaffNotationScoreInput {
    GrandStaffNotationScoreInput(identity: try #require(session.songIdentity), projection: try #require(session.notationProjection), measureSpans: session.measureSpans, facts: try #require(session.notationScoreFacts), attributeTimeline: session.attributeTimeline)
}

extension NativeBookWindowTests {
    @Test
    @MainActor
    func nativePreparedBookShowsManualResumeAndRestTransportInExistingWindow() async throws {
        let prepared = try await preparedBookFixture()
        let playback = BookTransportTestPlayback()
        let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper(), sequencerPlaybackService: playback)
        installBook(prepared, into: session)
        let owner = GrandStaffNotationPageViewModel()
        await owner.load(try bookInput(session))
        let plan = try #require(owner.plan)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try #require(scene.windows.first { $0.isKeyWindow })
        let original = window.rootViewController
        let size = window.bounds.size
        let minimum = scene.sizeRestrictions?.minimumSize
        let maximum = scene.sizeRestrictions?.maximumSize
        defer {
            session.shutdown()
            window.rootViewController = original
            scene.requestGeometryUpdate(.Vision(size: size, minimumSize: minimum, maximumSize: maximum))
        }
        scene.requestGeometryUpdate(.Vision(size: CGSize(width: 1240, height: 1000), minimumSize: CGSize(width: 1240, height: 1000), maximumSize: CGSize(width: 1240, height: 1000)))
        let controller = UIHostingController(rootView: PreparedBookNativeRoot(session: session))
        window.rootViewController = controller
        await TestAsyncWait.until("existing practice book window") { window.bounds.width >= 1239 && window.bounds.height >= 999 }
        session.startGuidingIfReady()
        session.skip()
        #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == plan.spreadCount - 1)
        try await Task.sleep(for: .seconds(1))
        _ = await session.suspendAndFlushProgress()
        session.resumeAfterSuspension()
        #expect(session.state == .ready && session.isRestoredSessionPaused)
        #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == plan.spreadCount - 1)
        try await Task.sleep(for: .seconds(1))
        session.retryMeasure(prepared.measureSpans[0].sourceMeasureID)
        session.roundConfigurationController.pendingPassage = try #require(PracticePassage(start: prepared.measureSpans[0].occurrenceID, end: prepared.measureSpans[127].occurrenceID))
        _ = session.applyPendingRoundConfiguration()
        #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 0)
        try await Task.sleep(for: .seconds(1))
        session.setAutoplayEnabled(true)
        session.startGuidingIfReady()
        await TestAsyncWait.until("native book autoplay started") { playback.sequence != nil }
        let rest = try #require(plan.pages.first { $0.index >= 2 }?.measures.first?.span)
        playback.seconds = session.tempoMap.timeSeconds(atTick: rest.startTick) - session.tempoMap.timeSeconds(atTick: prepared.steps[0].tick) + session.autoplayTimingLeadInSeconds + 0.001
        await TestAsyncWait.until("native rest page") { session.notationNavigationTick() == rest.startTick }
        #expect(plan.spreadIndex(containingTick: try #require(session.notationNavigationTick())) == 1)
        try await Task.sleep(for: .seconds(1))
        await session.pauseAutoplayPlayback()
        let paused = session.notationNavigationTick()
        playback.seconds += 10
        try await Task.sleep(for: .milliseconds(100))
        #expect(session.notationNavigationTick() == paused)
        session.clearPreparedSong()
        #expect(session.notationNavigationTick() == nil && session.notationProjection == nil)
        try await Task.sleep(for: .seconds(1))
    }

}

private struct PreparedBookNativeRoot: View {
    @Bindable var session: PracticeSessionViewModel

    var body: some View {
        if let identity = session.songIdentity, let projection = session.notationProjection, let facts = session.notationScoreFacts {
            GrandStaffNotationBookView(input: .init(identity: identity, projection: projection, measureSpans: session.measureSpans, facts: facts, attributeTimeline: session.attributeTimeline), navigationTick: session.notationNavigationTick(), overlay: session.activeNotationOverlay, practiceHandMode: session.practiceHandMode, navigationRange: session.activeRange?.tickRange, onNavigate: { session.navigateNotation(to: $0, identity: identity) })
                .padding(30)
        } else {
            ContentUnavailableView("没有已准备曲谱", systemImage: "music.note")
        }
    }
}

@MainActor
private final class BookTransportTestPlayback: PracticeSequencerPlaybackServiceProtocol {
    var seconds = 0.0
    var sequence: PracticeSequencerSequence?
    var loadCount = 0
    var holdNextSeconds = false
    var pendingSeconds: CheckedContinuation<TimeInterval, Never>?
    func warmUp() throws {}
    func stop(resetCommands: [PerformanceTransportCommand]) {}
    func load(sequence: PracticeSequencerSequence) throws { self.sequence = sequence; loadCount += 1 }
    func play(fromSeconds: TimeInterval) throws {}
    func currentSeconds() async -> TimeInterval {
        if holdNextSeconds {
            holdNextSeconds = false
            return await withCheckedContinuation { pendingSeconds = $0 }
        }
        return seconds
    }
    func releasePendingSeconds() {
        pendingSeconds?.resume(returning: seconds)
        pendingSeconds = nil
    }
    func pause() {}
    func resume() throws {}
    func setPlaybackRate(_ rate: Double) throws {}
    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds: TimeInterval) throws {}
    func execute(commands: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}
