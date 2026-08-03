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
    var autoplayTimingBaseTick: Int?
    var notationGuideScrollSchedule: [PracticeSessionNotationGuideScrollPoint] = []
    var notationGuideScrollScheduleBaseTick = 0
    var notationGuideScrollScheduleTaskGeneration = -1
    var notationGuideScrollScheduleTimelineEventCount = 0
    var audioRecognitionGeneration = 0
    var isAudioRecognitionRunning = false
}

struct PracticeSessionNotationGuideScrollPoint: Equatable {
    let timeSeconds: TimeInterval
    let tick: Int
}
