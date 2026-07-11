import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func libraryResumeSummaryUsesPassageHandAndTempo() async throws {
    let songID = UUID()
    let progress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: "r1"),
        activeConfiguration: try makePresentationConfiguration(),
        resumePoint: PracticeResumePoint(
            occurrenceID: try makePresentationConfiguration().passage.start,
            stepIndex: 0,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let repository = PresentationProgressRepository(progress: progress)
    let viewModel = SongLibraryViewModelTestHarness.make(
        practiceProgressRepository: repository
    )

    await viewModel.reloadPracticeProgress()

    #expect(viewModel.hasResumableProgress(entryID: songID))
    #expect(viewModel.practiceSummary(entryID: songID) == "上次练习：第 2–4 小节 · 右手 · 70%")
}

@MainActor
@Test
func prepareStartOverMovesToFirstActiveStepWithoutPlaying() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let session = PracticeSessionViewModel(
        pressDetectionService: PresentationPressDetector(),
        chordAttemptAccumulator: PresentationChordAccumulator(),
        sleeper: TaskSleeper()
    )
    let spans = presentationSpans()
    session.songIdentity = identity
    session.setSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
        ],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
    session.currentStepIndex = 1
    session.state = .ready
    session.isRestoredSessionPaused = true

    session.prepareStartOver()

    #expect(session.currentStepIndex == 0)
    #expect(session.state == .ready)
    #expect(session.isRestoredSessionPaused == false)
}

private func makePresentationConfiguration() throws -> PracticeRoundConfiguration {
    let startSource = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 1, sourceNumberToken: "2")
    let endSource = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 3, sourceNumberToken: "4")
    let passage = try #require(
        PracticePassage(
            start: PracticeMeasureOccurrenceID(sourceMeasureID: startSource, occurrenceIndex: 1),
            end: PracticeMeasureOccurrenceID(sourceMeasureID: endSource, occurrenceIndex: 3)
        )
    )
    return PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.7,
        loopEnabled: true,
        requiredSuccesses: 3
    )
}

private func presentationSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]
}

private actor PresentationProgressRepository: PracticeProgressRepositoryProtocol {
    private let progressValue: SongPracticeProgress

    init(progress: SongPracticeProgress) {
        progressValue = progress
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: [progressValue]))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        progressValue.identity == identity ? progressValue : nil
    }

    func upsert(_: SongPracticeProgress) {}
    func remove(songID _: UUID) {}
}

private struct PresentationPressDetector: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> { [] }
}

private final class PresentationChordAccumulator: ChordAttemptAccumulatorProtocol {
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
