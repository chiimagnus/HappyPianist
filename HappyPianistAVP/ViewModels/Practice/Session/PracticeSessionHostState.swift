import Foundation
import Observation
import Practice

@MainActor
@Observable
final class PracticeSessionHostState: PracticeSessionRuntimeState {
    var calibration: PianoCalibration?
    var keyboardGeometry: PianoKeyboardGeometry?
    var pressedNotes: Set<Int> = []
    var latestNoteOnMIDINotes: Set<Int> = []
    var latestKeyContactObservations: [PianoKeyContactObservation] = []
    var audioRecognitionErrorMessage: String?
    var audioRecognitionStatus: PracticeAudioRecognitionStatus = .idle
    var handGateState = HandGateState(
        isNearKeyboard: false,
        hasDownwardMotion: false,
        exactPressedNotes: [],
        confidenceBoost: 0
    )
    var audioRecognitionSuppressUntil: Date?
    var shouldResumeAudioRecognitionAfterManualReplay = false
    var highlightGuides: [PianoHighlightGuide] = []
    var currentHighlightGuideIndex: Int?
    var notationPositionTick: Int?
    var audioRecognitionGeneration = 0
    var isAudioRecognitionRunning = false
}
