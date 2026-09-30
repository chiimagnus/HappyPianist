import AVFAudio
import Foundation
import MusicXML
@testable import Notation
import Practice
import Testing
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
    playback.holdNextSeconds = true
    await TestAsyncWait.until("in-flight transport sample") { playback.pendingSeconds != nil }
    playback.seconds = session.tempoMap.timeSeconds(atTick: destination.endTick) - baseSeconds + session.autoplayTimingLeadInSeconds + 0.001
    await session.pauseAutoplayPlayback()
    let held = session.notationNavigationTick()
    playback.releasePendingSeconds()
    try await Task.sleep(for: .milliseconds(100))
    #expect(session.notationNavigationTick() == held)
    try await session.resumeAutoplayPlayback()
    await TestAsyncWait.until("resumed transport position") { session.notationNavigationTick() != held }
    session.setAutoplayEnabled(false)
    #expect(session.stateStore.autoplayNotationTick == nil)
    #expect(session.notationNavigationTick() == session.currentStep?.tick)
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
private func preparedBookFixture() async throws -> PreparedPractice {
    let measures = (1...128).map { index in
        let content = index == 1 || index == 128 ? "<pitch><step>C</step><octave>5</octave></pitch>" : "<rest measure=\"yes\"/>"
        return "<measure number=\"\(index)\">\(index == 1 ? "<attributes><divisions>1</divisions><staves>2</staves><time><beats>4</beats><beat-type>4</beat-type></time></attributes>" : "")<note>\(content)<duration>4</duration><type>whole</type><staff>1</staff></note></measure>"
    }.joined()
    let xml = "<score-partwise><part-list><score-part id=\"P1\"><part-name>Piano</part-name></score-part></part-list><part id=\"P1\">\(measures)</part></score-partwise>"
    let url = URL.temporaryDirectory.appending(path: "book-\(UUID()).musicxml")
    try Data(xml.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    return try await PracticePreparationService(diagnosticsReporter: InMemoryDiagnosticsReporter()).prepare(songID: UUID(), from: url, file: ImportedMusicXMLFile(fileName: url.lastPathComponent, storedURL: url, importedAt: .distantPast), options: .practice)
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
    await TestAsyncWait.until("replacement generation actually playing") { playback.sequence != nil && session.stateStore.autoplayNotationTick == destination }
    await builder.failFirstBuild()
    try await Task.sleep(for: .milliseconds(100))
    #expect(session.autoplayState == .playing)
    #expect(session.autoplayErrorMessage == nil)
    #expect(session.stateStore.autoplayNotationTick == destination)
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

@MainActor
private final class BookTransportTestPlayback: PracticeSequencerPlaybackServiceProtocol {
    var seconds = 0.0
    var sequence: PracticeSequencerSequence?
    var holdNextSeconds = false
    var pendingSeconds: CheckedContinuation<TimeInterval, Never>?
    func warmUp() throws {}
    func stop(resetCommands: [PerformanceTransportCommand]) {}
    func load(sequence: PracticeSequencerSequence) throws { self.sequence = sequence }
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
