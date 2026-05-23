import Foundation
@testable import LonelyPianistAVP

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
        manualAdvanceModeProvider: @escaping () -> ManualAdvanceMode = {
            ManualAdvanceMode.storageValue(from: UserDefaults.standard.string(forKey: "practiceManualAdvanceMode"))
        }
    ) {
        let resolvedPlaybackService = sequencerPlaybackService ?? NoopPracticeSequencerPlaybackService()
        let resolvedAudioStepAttemptAccumulator = audioStepAttemptAccumulator ?? AudioStepAttemptAccumulator()
        let resolvedHandPianoActivityGate = handPianoActivityGate ?? HandPianoActivityGate()
        self.init(
            pressDetectionService: pressDetectionService,
            chordAttemptAccumulator: chordAttemptAccumulator,
            sleeper: sleeper,
            sequencerPlaybackService: resolvedPlaybackService,
            audioRecognitionService: audioRecognitionService,
            practiceInputEventSource: practiceInputEventSource,
            audioStepAttemptAccumulator: resolvedAudioStepAttemptAccumulator,
            handPianoActivityGate: resolvedHandPianoActivityGate,
            manualAdvanceModeProvider: manualAdvanceModeProvider
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
