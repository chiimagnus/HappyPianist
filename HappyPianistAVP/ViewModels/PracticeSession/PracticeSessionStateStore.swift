import Foundation
import Observation

enum PracticeSessionState: Equatable {
    case idle
    case ready
    case guiding(stepIndex: Int)
    case completed
}

enum PracticeSessionAutoplayState: Equatable {
    case off
    case playing
}

struct PracticeSessionNotationGuideScrollPoint: Equatable {
    let timeSeconds: TimeInterval
    let tick: Int
}

@MainActor
@Observable
final class PracticeSessionStateStore {
    var state: PracticeSessionState = .idle
    var songIdentity: PracticeSongIdentity?
    var steps: [PracticeStep] = []

    var currentStepIndex: Int = 0 {
        didSet {
            if steps.isEmpty {
                state = .idle
            } else if currentStepIndex < steps.count {
                state = .guiding(stepIndex: currentStepIndex)
            }
        }
    }

    var autoplayState: PracticeSessionAutoplayState = .off
    var calibration: PianoCalibration?
    var keyboardGeometry: PianoKeyboardGeometry?
    var pressedNotes: Set<Int> = []
    var latestNoteOnMIDINotes: Set<Int> = []
    var latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
    var isSustainPedalDown = false
    var audioRecognitionErrorMessage: String?
    var audioPlaybackErrorMessage: String?
    var autoplayErrorMessage: String?

    var audioRecognitionStatus: PracticeAudioRecognitionStatus = .idle
    var audioRecognitionDebugSnapshot: PracticeAudioRecognitionDebugSnapshot = .empty
    var handGateState = HandGateState(
        isNearKeyboard: false,
        hasDownwardMotion: false,
        exactPressedNotes: [],
        confidenceBoost: 0
    )
    var noteMatchTolerance: Int = 1

    var tempoMap = MusicXMLTempoMap(tempoEvents: [])
    var measureSpans: [MusicXMLMeasureSpan] = []
    var manualReplayGeneration = 0
    var isManualReplayPlaying = false
    var shouldResumeAudioRecognitionAfterManualReplay = false
    var pedalTimeline: MusicXMLPedalTimeline?
    var fermataTimeline: MusicXMLFermataTimeline?
    var attributeTimeline: MusicXMLAttributeTimeline?
    var slurTimeline: MusicXMLSlurTimeline?
    var autoplayTimeline: AutoplayPerformanceTimeline = .empty
    var highlightGuides: [PianoHighlightGuide] = []
    var currentHighlightGuideIndex: Int?
    var autoplayTimingBaseTick: Int?

    var notationGuideScrollSchedule: [PracticeSessionNotationGuideScrollPoint] = []
    var notationGuideScrollScheduleBaseTick: Int = 0
    var notationGuideScrollScheduleTaskGeneration: Int = -1
    var notationGuideScrollScheduleTimelineEventCount: Int = 0

    var audioRecognitionGeneration = 0
    var isAudioRecognitionRunning = false
    var practiceInputGeneration = 0
    var isPracticeInputRunning = false
    var practiceInputActiveSinceUptimeSeconds: TimeInterval?
    var practiceInputLastResetStepIndex: Int?
    var practiceInputDebugLastLoggedAtUptimeSeconds: TimeInterval = 0
    var practiceInputDebugLastMessage: String?
    var audioRecognitionSuppressUntil: Date?
    var practiceAudioRecognitionDetectorModeSnapshot: PracticeAudioRecognitionDetectorMode = .harmonicTemplate
    var harmonicTemplateTuningProfileSnapshot: HarmonicTemplateTuningProfile = .lowLatencyDefault
}
