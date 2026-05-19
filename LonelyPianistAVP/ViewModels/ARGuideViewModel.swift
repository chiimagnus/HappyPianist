import ARKit
import Dispatch
import Foundation
import Observation
import os
import simd

@MainActor
@Observable
final class ARGuideViewModel {
    private let practiceInputLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "PracticeInput-Recording"
    )
    typealias CalibrationPhase = CalibrationFlowViewModel.CalibrationPhase
    typealias PracticeLocalizationFailure = PracticeLocalizationViewModel.PracticeLocalizationFailure
    typealias PracticeLocalizationState = PracticeLocalizationViewModel.PracticeLocalizationState

    // MARK: - Dependencies
    let appState: AppState
    let flowState: FlowState
    let calibrationFlowViewModel: CalibrationFlowViewModel
    let practiceLocalizationViewModel: PracticeLocalizationViewModel

    // MARK: - Practice Session (P3: split target)
    let practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol
    var practiceSessionViewModel: PracticeSessionViewModel
    var latestPreparedPractice: PreparedPractice?

    // MARK: - Tracking & Long-Lived Tasks (P3: split target)
    var handTrackingConsumerTask: Task<Void, Never>?
    var currentTrackingMode: ARTrackingMode?
    var virtualPianoGuidanceUpdateTask: Task<Void, Never>?

    // MARK: - UI/Flow State (P3: split target)
    var isVirtualPianoEnabled = false
    var isVirtualPianoPlaced = false
    var isVirtualPerformerEnabled = false
    var isAIPerformanceActive = false
    var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] = []
    var lastImprovStatusText: String?
    var latestDeviceWorldPosition: SIMD3<Float>?

    // MARK: - Gaze & Placement (P3: split target)
    let gazePlaneDiskConfirmation = GazePlaneDiskConfirmationViewModel()
    let gazePlaneHitTestService = GazePlaneHitTestService()
    var latestGazePlaneHit: PlaneHit?
    var latestGazeRayOriginWorld: SIMD3<Float>?

    // MARK: - Backend / Improv (P3: split target)
    let backendDiscoveryService = BonjourBackendDiscoveryService()

    // MARK: - Recording (P3: split target)
    let takeLibraryViewModel = TakeLibraryViewModel()
    @ObservationIgnored
    lazy var midiRecordingCoordinator: MIDIRecordingCoordinator = MIDIRecordingCoordinator(
        logger: practiceInputLogger,
        onStateChanged: { [weak self] state in
            guard let self else { return }
            self.isRecording = state.isRecording
            self.recordingStartDate = state.recordingStartDate
        },
        onTakeRecorded: { [weak self] take in
            self?.takeLibraryViewModel.addTake(take)
        },
        onMIDI1Event: { [weak self] event in
            self?.aiPerformanceCoordinator.recordMIDI1EventForPhraseRecordingIfNeeded(event)
        },
        onMIDI2Event: { [weak self] event in
            self?.aiPerformanceCoordinator.recordMIDI2EventForPhraseRecordingIfNeeded(event)
        }
    )
    @ObservationIgnored
    lazy var aiPerformanceCoordinator: AIPerformanceCoordinator = AIPerformanceCoordinator(
        logger: Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
            category: "AIPerformanceCoordinator"
        ),
        backendDiscoveryService: backendDiscoveryService,
        onStateChanged: { [weak self] state in
            guard let self else { return }
            self.isAIPerformanceActive = state.isAIPerformanceActive
            self.latestAIPerformanceSchedule = state.latestSchedule
            self.lastImprovStatusText = state.lastImprovStatusText
        }
    )
    let takePlaybackController = TakePlaybackController(
        playbackService: AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
    )
    let takePlaybackViewModel: TakePlaybackViewModel
    var isRecording = false
    var recordingStartDate: Date?
    let pianoModeRegistry: PianoModeRegistryProtocol

    init(
        appState: AppState,
        flowState: FlowState,
        pianoModeRegistry: PianoModeRegistryProtocol,
        practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol
    ) {
        self.appState = appState
        self.flowState = flowState
        calibrationFlowViewModel = CalibrationFlowViewModel(appState: appState)
        practiceLocalizationViewModel = PracticeLocalizationViewModel(appState: appState)
        self.pianoModeRegistry = pianoModeRegistry
        self.practiceSessionViewModelFactory = practiceSessionViewModelFactory
        takePlaybackViewModel = TakePlaybackViewModel(controller: takePlaybackController)
        practiceSessionViewModel = practiceSessionViewModelFactory
            .makePracticeSessionViewModel(for: flowState.selectedPianoModeID)
        setupAppStateCallbacks()
    }

    var selectedPianoMode: (any PianoModeProtocol)? {
        pianoModeRegistry.mode(for: flowState.selectedPianoModeID)
    }

    var isVirtualPianoMode: Bool {
        selectedPianoMode?.isVirtualPianoMode == true
    }

    private func setupAppStateCallbacks() {
        flowState.onStepsImported = { [weak self] prepared in
            guard let self else { return }
            latestPreparedPractice = prepared
            practiceSessionViewModel.setSteps(
                prepared.steps,
                tempoMap: prepared.tempoMap,
                pedalTimeline: prepared.pedalTimeline,
                fermataTimeline: prepared.fermataTimeline,
                attributeTimeline: prepared.attributeTimeline,
                slurTimeline: prepared.slurTimeline,
                noteSpans: prepared.noteSpans,
                highlightGuides: prepared.highlightGuides,
                measureSpans: prepared.measureSpans
            )
            appState.applySessionIfPossible()
            if isVirtualPerformerEnabled {
                setPracticeVirtualPerformerEnabled(true)
            }
        }
        appState.onCalibrationCleared = { [weak self] in
            self?.practiceSessionViewModel.clearCalibration()
        }
        appState.onSessionReset = { [weak self] in
            self?.practiceSessionViewModel.resetSession()
        }
        appState.onApplyKeyboardGeometry = { [weak self] geometry, calibration in
            self?.practiceSessionViewModel.applyKeyboardGeometry(geometry, calibration: calibration)
        }
    }

    func replacePracticeSessionViewModel() {
        let next = practiceSessionViewModelFactory.makePracticeSessionViewModel(for: flowState.selectedPianoModeID)

        practiceSessionViewModel.shutdown()
        practiceSessionViewModel = next
        aiPerformanceCoordinator.updatePracticeSession(next)

        if let prepared = latestPreparedPractice {
            practiceSessionViewModel.setSteps(
                prepared.steps,
                tempoMap: prepared.tempoMap,
                pedalTimeline: prepared.pedalTimeline,
                fermataTimeline: prepared.fermataTimeline,
                attributeTimeline: prepared.attributeTimeline,
                slurTimeline: prepared.slurTimeline,
                noteSpans: prepared.noteSpans,
                highlightGuides: prepared.highlightGuides,
                measureSpans: prepared.measureSpans
            )
        }

        appState.applySessionIfPossible()
        if isVirtualPerformerEnabled {
            setPracticeVirtualPerformerEnabled(true)
        }

        midiRecordingCoordinator.refreshMIDISubscriptionIfNeeded(
            usesBluetoothMIDIInput: selectedPianoMode?.usesBluetoothMIDIInput == true,
            eventSource: practiceSessionViewModel.practiceInputEventSource
        )
    }

}
