import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func restoredPracticeStaysReadyAndSilentUntilExplicitStart() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let passage = try #require(PracticePassage(start: spans[0].occurrenceID, end: spans[1].occurrenceID))
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.7,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: configuration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let repository = ResumeRepository(progress: progress)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let playback = CapturingResumePlaybackService()
    let session = PracticeSessionViewModel(
        pressDetectionService: ResumeNoopPressDetectionService(),
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        progressCoordinator: coordinator
    )
    session.songIdentity = identity
    session.setSteps(makeResumeSteps(), tempoMap: MusicXMLTempoMap(tempoEvents: []), measureSpans: spans)

    await session.restoreProgressIfAvailable()

    #expect(session.state == .ready)
    #expect(session.currentStepIndex == 1)
    #expect(session.activeRoundConfiguration == configuration)
    #expect(session.isRestoredSessionPaused)
    #expect(playback.oneShotCount == 0)
    #expect(playback.playCount == 0)

    session.startGuidingIfReady()
    #expect(session.state == .guiding(stepIndex: 1))
    #expect(playback.oneShotCount == 1)
}

@MainActor
@Test
func invalidRestoredPassageFailsClosed() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeResumeSpans()
    let missingSource = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 99)
    let missingOccurrence = PracticeMeasureOccurrenceID(sourceMeasureID: missingSource, occurrenceIndex: 99)
    let passage = try #require(PracticePassage(start: missingOccurrence, end: missingOccurrence))
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: 3
        ),
        updatedAt: .now
    )
    let playback = CapturingResumePlaybackService()
    let session = PracticeSessionViewModel(
        pressDetectionService: ResumeNoopPressDetectionService(),
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback,
        progressCoordinator: PracticeProgressCoordinator(repository: ResumeRepository(progress: progress))
    )
    session.songIdentity = identity
    session.setSteps(makeResumeSteps(), tempoMap: MusicXMLTempoMap(tempoEvents: []), measureSpans: spans)

    await session.restoreProgressIfAvailable()
    session.startGuidingIfReady()
    session.playCurrentStepSound()
    session.setAutoplayEnabled(true)

    #expect(session.activeRangeDiagnostic == .passageBoundaryNotFound)
    #expect(session.state == .ready)
    #expect(session.currentStep == nil)
    #expect(session.notationMeasureSpans.isEmpty)
    #expect(session.autoplayTimeline == .empty)
    #expect(playback.oneShotCount == 0)
    #expect(playback.playCount == 0)
}


@MainActor
@Test
func suspendedPracticeReturnsToPausedReadyAndCanRestartInput() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let repository = ResumeRepository(progress: nil)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let session = PracticeSessionViewModel(
        pressDetectionService: ResumeNoopPressDetectionService(),
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: coordinator
    )
    session.songIdentity = identity
    session.setSteps(
        makeResumeSteps(),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: makeResumeSpans()
    )
    await session.restoreProgressIfAvailable()
    session.startGuidingIfReady()
    await session.suspendAndFlushProgress()

    #expect(session.acceptsPracticeAttempts == false)
    session.resumeAfterSuspension()
    #expect(session.acceptsPracticeAttempts)
    #expect(session.state == .ready)
    #expect(session.isRestoredSessionPaused)
}

@MainActor
@Test
func pausedPracticeRejectsAdvanceEffectWithoutPlayback() {
    let playback = CapturingResumePlaybackService()
    let session = PracticeSessionViewModel(
        pressDetectionService: ResumeNoopPressDetectionService(),
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        sequencerPlaybackService: playback
    )
    session.setSteps(makeResumeSteps(), tempoMap: MusicXMLTempoMap(tempoEvents: []), measureSpans: makeResumeSpans())

    session.handle(effect: .advanceToNextStep)

    #expect(session.state == .ready)
    #expect(session.currentStepIndex == 0)
    #expect(playback.oneShotCount == 0)
    #expect(playback.playCount == 0)
}

@MainActor
@Test
func flushAndShutdownPersistsLatestResumePointBeforeTeardown() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let repository = ResumeRepository(progress: nil)
    let coordinator = PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    let session = PracticeSessionViewModel(
        pressDetectionService: ResumeNoopPressDetectionService(),
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: coordinator
    )
    let spans = makeResumeSpans()
    session.songIdentity = identity
    session.setSteps(makeResumeSteps(), tempoMap: MusicXMLTempoMap(tempoEvents: []), measureSpans: spans)
    await session.restoreProgressIfAvailable()
    session.startGuidingIfReady()
    session.recordAttemptOutcome(
        .matched(
            evidence: PracticeAttemptEvidence(
                expectedNotes: [60],
                observedNotes: [60],
                handMode: .both,
                source: .midi,
                isPartialEvidence: false,
                debugMessage: "matched"
            )
        )
    )

    await session.flushAndShutdown()

    #expect(await repository.progress(for: identity)?.resumePoint?.stepIndex == 0)
    #expect(session.acceptsPracticeAttempts == false)
}

@MainActor
@Test
func navigationWithoutAttemptPersistsLatestResumePoint() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let repository = ResumeRepository(progress: nil)
    let session = PracticeSessionViewModel(
        pressDetectionService: ResumeNoopPressDetectionService(),
        chordAttemptAccumulator: ResumeNoopChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository, checkpointDelay: .seconds(60))
    )
    let spans = makeResumeSpans()
    session.songIdentity = identity
    session.setSteps(makeResumeSteps(), tempoMap: MusicXMLTempoMap(tempoEvents: []), measureSpans: spans)
    await session.restoreProgressIfAvailable()
    session.startGuidingIfReady()

    session.moveToStep(1, shouldPlaySound: false)
    await session.flushAndShutdown()

    #expect(await repository.progress(for: identity)?.resumePoint?.stepIndex == 1)
    #expect(await repository.progress(for: identity)?.resumePoint?.occurrenceID == spans[1].occurrenceID)
}

private func makeResumeSteps() -> [PracticeStep] {
    [
        PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
    ]
}

private func makeResumeSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]
}

private actor ResumeRepository: PracticeProgressRepositoryProtocol {
    private var stored: SongPracticeProgress?

    init(progress: SongPracticeProgress?) {
        stored = progress
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: stored.map { [$0] } ?? []))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        stored?.identity == identity ? stored : nil
    }

    func upsert(_ progress: SongPracticeProgress) {
        stored = progress
    }

    func remove(songID: UUID) {
        if stored?.identity.songID == songID { stored = nil }
    }
}

private final class CapturingResumePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var oneShotCount = 0
    private(set) var playCount = 0
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws { playCount += 1 }
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws { oneShotCount += 1 }
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private struct ResumeNoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> { [] }
}

private final class ResumeNoopChordAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes: Set<Int>,
        expectedNotes: [Int],
        tolerance _: Int,
        at _: Date
    ) -> StepAttemptMatchResult {
        .insufficientEvidence(
            evidence: PracticeAttemptEvidence(
                expectedNotes: Set(expectedNotes),
                observedNotes: pressedNotes,
                handMode: .both,
                source: .handContact,
                isPartialEvidence: false,
                debugMessage: "noop"
            )
        )
    }

    func reset() {}
}
