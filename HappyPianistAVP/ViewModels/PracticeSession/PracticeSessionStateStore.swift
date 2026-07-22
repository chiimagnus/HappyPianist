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
    var sessionProgress: SongPracticeProgress?
    var attemptReductionState = PracticeAttemptReductionState()
    var latestFeedbackEvent: PracticeFeedbackEvent?
    var currentCoachingDecision: CoachingDecision?
    var feedbackEventSequence = 0
    var songIdentity: PracticeSongIdentity?
    var progressGeneration: Int?
    var isRestoredSessionPaused = false
    var acceptsPracticeAttempts = true
    var activeRoundConfiguration: PracticeRoundConfiguration?
    var measureIndex: PracticeMeasureIndex?
    var activeRange: PracticeActiveRange?
    var activeRangeDiagnostic: PracticeMeasureIndexDiagnostic?
    var isActiveRangeInvalid: Bool {
        activeRangeDiagnostic != nil
    }

    var activeManualAdvanceMode: ManualAdvanceMode = .step
    var activeSoundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
    var roundGeneration = 0
    var performancePlan: ScorePerformancePlan? {
        didSet {
            tempoMap = MusicXMLTempoMap(performanceEvents: performancePlan?.tempoEvents ?? [])
            performanceEventIDByDescription = Dictionary(
                uniqueKeysWithValues: (performancePlan?.noteEvents ?? []).map {
                    ($0.id.description, $0.id)
                }
            )
        }
    }
    private(set) var performanceEventIDByDescription: [String: ScorePerformanceNoteEventID] = [:]
    var notationProjection: ScoreNotationProjection?
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
    var latestKeyContactObservations: [PianoKeyContactObservation] = []
    var isSustainPedalDown = false
    var audioRecognitionErrorMessage: String?
    var audioPlaybackErrorMessage: String?
    var autoplayErrorMessage: String?

    var audioRecognitionStatus: PracticeAudioRecognitionStatus = .idle
    var handGateState = HandGateState(
        isNearKeyboard: false,
        hasDownwardMotion: false,
        exactPressedNotes: [],
        confidenceBoost: 0
    )
    private(set) var tempoMap = MusicXMLTempoMap(performanceEvents: [])
    var measureSpans: [MusicXMLMeasureSpan] = []
    var manualReplayGeneration = 0
    var isManualReplayPlaying = false
    var shouldResumeAudioRecognitionAfterManualReplay = false
    var attributeTimeline: MusicXMLAttributeTimeline?
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
    var audioRecognitionSuppressUntil: Date?
}
