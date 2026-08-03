import Foundation
import MusicXML
import Observation

public enum PracticeSessionAutoplayState: Equatable, Sendable {
    case off
    case playing
}

@MainActor
@Observable
open class PracticeSessionRuntimeState {
    public var state: PracticeSessionState = .idle
    public var sessionProgress: SongPracticeProgress?
    public var attemptReductionState = PracticeAttemptReductionState()
    public var latestFeedbackEvent: PracticeFeedbackEvent?
    public var currentCoachingDecision: CoachingDecision?
    public var feedbackEventSequence = 0
    public var songIdentity: PracticeSongIdentity?
    public var progressGeneration: Int?
    public var isRestoredSessionPaused = false
    public var acceptsPracticeAttempts = true
    public var activeRoundConfiguration: PracticeRoundConfiguration?
    public var measureIndex: PracticeMeasureIndex?
    public var activeRange: PracticeActiveRange?
    public var activeRangeDiagnostic: PracticeMeasureIndexDiagnostic?
    public var isActiveRangeInvalid: Bool {
        activeRangeDiagnostic != nil
    }

    public var activeManualAdvanceMode: ManualAdvanceMode = .step
    public var activeSoundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
    public var roundGeneration = 0
    public var performancePlan: ScorePerformancePlan? {
        didSet {
            tempoMap = MusicXMLTempoMap(performanceEvents: performancePlan?.tempoEvents ?? [])
            performanceEventIDByDescription = Dictionary(
                uniqueKeysWithValues: (performancePlan?.noteEvents ?? []).map {
                    ($0.id.description, $0.id)
                }
            )
        }
    }

    public private(set) var performanceEventIDByDescription: [String: ScorePerformanceNoteEventID] = [:]
    public var notationProjection: ScoreNotationProjection?
    public var steps: [PracticeStep] = []

    public var currentStepIndex: Int = 0 {
        didSet {
            if steps.isEmpty {
                state = .idle
            } else if currentStepIndex < steps.count {
                state = .guiding(stepIndex: currentStepIndex)
            }
        }
    }

    public var autoplayState: PracticeSessionAutoplayState = .off
    public var isSustainPedalDown = false
    public var audioPlaybackErrorMessage: String?
    public var autoplayErrorMessage: String?
    public private(set) var tempoMap = MusicXMLTempoMap(performanceEvents: [])
    public var measureSpans: [MusicXMLMeasureSpan] = []
    public var manualReplayGeneration = 0
    public var isManualReplayPlaying = false
    public var attributeTimeline: MusicXMLAttributeTimeline?
    public var autoplayTimeline: AutoplayPerformanceTimeline = .empty
    public var isPracticeInputRunning = false

    public init() {}
}

extension PracticeSessionRuntimeState: PracticeRoundConfigurationStateStoring {}

public extension PracticeSessionRuntimeState {
    func recordPlaybackError(_ error: Error) {
        guard audioPlaybackErrorMessage == nil else { return }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           description.isEmpty == false
        {
            audioPlaybackErrorMessage = description
        } else {
            audioPlaybackErrorMessage = String(describing: error)
        }
    }
}
