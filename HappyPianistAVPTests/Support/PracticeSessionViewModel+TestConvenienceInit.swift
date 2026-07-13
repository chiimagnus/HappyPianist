import Foundation
@testable import HappyPianistAVP

extension PracticeSessionViewModel {
    @MainActor
    convenience init(
        pressDetectionService: PressDetectionServiceProtocol,
        chordAttemptAccumulator: ChordAttemptAccumulatorProtocol,
        sleeper: SleeperProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol? = nil,
        audioRecognitionService: PracticeAudioRecognitionServiceProtocol? = nil,
        practiceInputEventSource: PracticeInputEventSourceProtocol? = nil,
        audioStepAttemptAccumulator: AudioStepAttemptAccumulator? = nil,
        handPianoActivityGate: HandPianoActivityGate? = nil,
        progressCoordinator: PracticeProgressCoordinator? = nil,
        manualAdvanceMode: ManualAdvanceMode = .step
    ) {
        let resolvedPlaybackService = sequencerPlaybackService ?? NoopPracticeSequencerPlaybackService()
        let resolvedAudioStepAttemptAccumulator = audioStepAttemptAccumulator ?? AudioStepAttemptAccumulator()
        let resolvedHandPianoActivityGate = handPianoActivityGate ?? HandPianoActivityGate()
        let settingsProvider = TestPracticeSessionSettingsProvider(
            manualAdvanceMode: manualAdvanceMode
        )
        self.init(
            pressDetectionService: pressDetectionService,
            chordAttemptAccumulator: chordAttemptAccumulator,
            sleeper: sleeper,
            sequencerPlaybackService: resolvedPlaybackService,
            audioRecognitionService: audioRecognitionService,
            practiceInputEventSource: practiceInputEventSource,
            audioStepAttemptAccumulator: resolvedAudioStepAttemptAccumulator,
            handPianoActivityGate: resolvedHandPianoActivityGate,
            settingsProvider: settingsProvider,
            progressCoordinator: progressCoordinator
        )
    }
}

private final class NoopPracticeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    func warmUp() throws {}
    func stop() {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws {}
    func currentSeconds() -> TimeInterval {
        0
    }

    func playOneShot(noteOns _: [PracticeOneShotNoteOn], durationSeconds _: TimeInterval) throws {}
    func startLiveNotes(midiNotes _: Set<Int>) throws {}
    func stopLiveNotes(midiNotes _: Set<Int>) {}
    func stopAllLiveNotes() {}
}

private struct TestPracticeSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode
    let practiceHandMode: PracticeHandMode = .both
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private let defaultTestPracticeSongIdentity = PracticeSongIdentity(
    songID: UUID(),
    scoreRevision: "test-score"
)

extension PracticeSessionViewModel {
    @MainActor
    func setSteps(
        _ steps: [PracticeStep],
        tempoMap: MusicXMLTempoMap,
        pedalTimeline: MusicXMLPedalTimeline? = nil,
        fermataTimeline: MusicXMLFermataTimeline? = nil,
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        slurTimeline: MusicXMLSlurTimeline? = nil,
        highlightGuides: [PianoHighlightGuide] = [],
        measureSpans: [MusicXMLMeasureSpan] = []
    ) {
        let resolvedMeasureSpans = measureSpans.isEmpty
            ? [Self.syntheticMeasureSpan(for: steps)]
            : measureSpans
        installPreparedSteps(
            steps,
            identity: songIdentity ?? defaultTestPracticeSongIdentity,
            tempoMap: tempoMap,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            attributeTimeline: attributeTimeline,
            slurTimeline: slurTimeline,
            highlightGuides: highlightGuides,
            measureSpans: resolvedMeasureSpans
        )
    }

    private static func syntheticMeasureSpan(for steps: [PracticeStep]) -> MusicXMLMeasureSpan {
        let startTick = steps.map(\.tick).min() ?? 0
        let finalTick = steps.map(\.tick).max() ?? startTick
        return MusicXMLMeasureSpan(
            partID: "test-part",
            measureNumber: 1,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            occurrenceIndex: 0,
            startTick: startTick,
            endTick: finalTick + 1
        )
    }
}
