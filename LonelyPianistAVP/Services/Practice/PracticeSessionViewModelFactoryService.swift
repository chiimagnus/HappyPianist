import Foundation

final class PracticeSessionViewModelFactoryService: PracticeSessionViewModelFactoryProtocol {
    nonisolated init() {}

    func makePracticeSessionViewModel(for pianoKind: PianoKind?) -> PracticeSessionViewModel {
        switch pianoKind {
        case .realBluetoothMIDI:
            PracticeSessionViewModel(
                pressDetectionService: PressDetectionService(),
                chordAttemptAccumulator: ChordAttemptAccumulator(),
                sleeper: TaskSleeper(),
                sequencerPlaybackService: AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2"),
                audioRecognitionService: nil,
                practiceInputEventSource: BluetoothMIDIInputEventSourceService()
            )

        case .realAudio, .virtual, .none:
            PracticeSessionViewModel()
        }
    }
}
