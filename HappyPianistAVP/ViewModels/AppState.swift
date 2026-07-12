import ARKit
import Observation
import simd

/// Maintains app-wide state
@MainActor
@Observable
class AppState {
    enum PracticeCalibrationResolutionResult: Equatable {
        case resolved
        case missingStoredCalibration
        case anchorMissing(id: UUID)
        case anchorNotTracked(id: UUID)
        case anchorsTooClose(distanceMeters: Float)
        case devicePoseUnavailable
    }

    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    enum ImmersiveMode {
        case calibration
        case practice
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var immersiveMode: ImmersiveMode = .practice

    let arTrackingService: ARTrackingServiceProtocol

    var storedCalibration: StoredWorldAnchorCalibration?

    /// Cached placement for the "virtual piano" mode (not the real-piano calibration flow).
    /// Uses a persisted `WorldAnchor` ID so ARKit can restore it across sessions/spaces.
    var cachedVirtualPianoWorldAnchorID: UUID?

    var calibration: PianoCalibration? {
        didSet { applySessionIfPossible() }
    }

    let calibrationCaptureService: CalibrationPointCaptureService
    var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint?
    var calibrationStatusMessage: String?

    private let calibrationRepository: CalibrationRepositoryProtocol
    private let keyGeometryService: PianoKeyGeometryServiceProtocol

    var practiceSetupState = PracticeSetupState()
    var pianoModeRegistry: PianoModeRegistryProtocol!
    var windowState: WindowTransitionState!
    var arGuideViewModel: ARGuideViewModel!
    var songLibraryViewModel: SongLibraryViewModel!
    var practiceProgressRepository: (any PracticeProgressRepositoryProtocol)!
    var practiceProgressCoordinator: PracticeProgressCoordinator!
    var diagnosticsReporter: (any DiagnosticsReporting)!
    var diagnosticsViewModel: DiagnosticsViewModel!

    init(
        arTrackingService: ARTrackingServiceProtocol,
        calibrationCaptureService: CalibrationPointCaptureService,
        calibrationRepository: CalibrationRepositoryProtocol,
        keyGeometryService: PianoKeyGeometryServiceProtocol
    ) {
        self.arTrackingService = arTrackingService
        self.calibrationCaptureService = calibrationCaptureService
        self.calibrationRepository = calibrationRepository
        self.keyGeometryService = keyGeometryService
    }

    /// Convenience init for tests/previews that don't need to control service instances.
    convenience init(
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil
    ) {
        self.init(
            arTrackingService: arTrackingService ?? ARTrackingService(),
            calibrationCaptureService: CalibrationPointCaptureService(),
            calibrationRepository: CalibrationRepository(),
            keyGeometryService: keyGeometryService ?? PianoKeyGeometryService()
        )
    }

    func beginCalibrationRecapture() {
        let persistedAnchorIDs = Set([
            storedCalibration?.a0AnchorID,
            storedCalibration?.c8AnchorID,
        ].compactMap(\.self))
        let capturedAnchorIDs = Set([
            calibrationCaptureService.a0AnchorID,
            calibrationCaptureService.c8AnchorID,
        ].compactMap(\.self)).subtracting(persistedAnchorIDs)

        guard capturedAnchorIDs.isEmpty == false else {
            resetCalibrationCaptureState()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await calibrationRepository.removeCapturedAnchorsIfPossible(
                capturedAnchorIDs,
                arTrackingService: arTrackingService
            )
            resetCalibrationCaptureState()
        }
    }

    func loadStoredCalibrationIfPossible() {
        do {
            guard let stored = try calibrationRepository.loadStoredCalibration() else { return }
            storedCalibration = stored
            calibrationStatusMessage = "已加载校准（待定位）"
        } catch {
            calibrationStatusMessage = "加载校准失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveCalibrationIfPossible() -> Bool {
        guard
            let a0AnchorID = calibrationCaptureService.a0AnchorID,
            let c8AnchorID = calibrationCaptureService.c8AnchorID,
            a0AnchorID != c8AnchorID
        else {
            calibrationStatusMessage = "校准信息不完整"
            return false
        }

        let previousStoredCalibration = storedCalibration

        do {
            let savedCalibration = try calibrationRepository.saveCalibration(
                a0AnchorID: a0AnchorID,
                c8AnchorID: c8AnchorID,
                whiteKeyWidth: calibration?.whiteKeyWidth ?? storedCalibration?.whiteKeyWidth ?? 0.0235
            )
            storedCalibration = savedCalibration
            calibration = nil
            pendingCalibrationCaptureAnchor = nil
            calibrationCaptureService.reset()
            calibrationStatusMessage = "已保存校准（待定位）"

            if let previousStoredCalibration {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await calibrationRepository.removeOldAnchorsIfPossible(
                        previous: previousStoredCalibration,
                        current: savedCalibration,
                        arTrackingService: arTrackingService
                    )
                }
            }
            return true
        } catch {
            calibrationStatusMessage = "保存校准失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearRuntimeCalibrationForPracticeRelocation() {
        calibration = nil
        onCalibrationCleared?()
    }

    var onCalibrationCleared: (() -> Void)?

    func resolveRuntimeCalibrationFromTrackedAnchors() -> PracticeCalibrationResolutionResult {
        guard let storedCalibration else {
            return .missingStoredCalibration
        }

        guard let a0Anchor = arTrackingService.worldAnchorsByID[storedCalibration.a0AnchorID] else {
            return .anchorMissing(id: storedCalibration.a0AnchorID)
        }

        guard let c8Anchor = arTrackingService.worldAnchorsByID[storedCalibration.c8AnchorID] else {
            return .anchorMissing(id: storedCalibration.c8AnchorID)
        }

        guard a0Anchor.isTracked else {
            return .anchorNotTracked(id: storedCalibration.a0AnchorID)
        }

        guard c8Anchor.isTracked else {
            return .anchorNotTracked(id: storedCalibration.c8AnchorID)
        }

        let a0Point = worldAnchorPoint(from: a0Anchor)
        let c8Point = worldAnchorPoint(from: c8Anchor)

        let distanceMeters = simd_length(c8Point - a0Point)
        guard distanceMeters > 0.05 else {
            return .anchorsTooClose(distanceMeters: distanceMeters)
        }

        let planeY = (a0Point.y + c8Point.y) / 2

        // Interpret calibrated A0/C8 as the keyboard's *front edge line* (keyboard-local z = 0).
        // We still need to place highlights and hit regions at key centers, which are offset by
        // ±keyDepth/2 along the keyboard-local Z axis. Determine the correct sign using the current
        // device pose (which side the user is on).
        let frontEdgeToKeyCenterLocalZ: Float
        if let frame = KeyboardFrame(a0World: a0Point, c8World: c8Point, planeHeight: planeY) {
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard
                let deviceAnchor = arTrackingService.worldTrackingProvider.queryDeviceAnchor(atTimestamp: timestamp),
                deviceAnchor.isTracked
            else {
                return .devicePoseUnavailable
            }

            let deviceTransform = deviceAnchor.originFromAnchorTransform
            let devicePos = SIMD3<Float>(
                deviceTransform.columns.3.x,
                deviceTransform.columns.3.y,
                deviceTransform.columns.3.z
            )

            let origin = frame.originWorld
            let toDevice = SIMD3<Float>(devicePos.x - origin.x, 0, devicePos.z - origin.z)
            let toDeviceLen = simd_length(toDevice)
            if toDeviceLen > 1e-4 {
                let toDeviceDir = toDevice / toDeviceLen
                let zAxis = frame.zAxisWorld
                // If the device is on +Z side, keyboard interior is -Z; otherwise interior is +Z.
                let interiorIsNegativeZ = simd_dot(toDeviceDir, zAxis) > 0
                frontEdgeToKeyCenterLocalZ = (interiorIsNegativeZ ? -1 : 1) *
                    (PianoKeyGeometryService.whiteKeyDepthMeters / 2)
            } else {
                // Degenerate; fall back to "no offset" rather than guessing a direction.
                frontEdgeToKeyCenterLocalZ = 0
            }
        } else {
            frontEdgeToKeyCenterLocalZ = 0
        }

        calibration = PianoCalibration(
            a0: a0Point,
            c8: c8Point,
            planeHeight: planeY,
            whiteKeyWidth: storedCalibration.whiteKeyWidth,
            frontEdgeToKeyCenterLocalZ: frontEdgeToKeyCenterLocalZ
        )

        return .resolved
    }

    private func resetCalibrationCaptureState() {
        pendingCalibrationCaptureAnchor = nil
        calibrationStatusMessage = "请重新校准"
        calibration = nil
        calibrationCaptureService.reset()
        onSessionReset?()
    }

    var onSessionReset: (() -> Void)?

    func applySessionIfPossible() {
        guard let calibration else { return }
        guard let keyboardGeometry = keyGeometryService.generateKeyboardGeometry(from: calibration) else { return }
        onApplyKeyboardGeometry?(keyboardGeometry, calibration)
    }

    var onApplyKeyboardGeometry: ((PianoKeyboardGeometry, PianoCalibration) -> Void)?

    func applyPreparedPractice(_ prepared: PreparedPractice) async {
        practiceSetupState.setImportedSteps(from: prepared)
        await arGuideViewModel?.applyPreparedPractice(prepared)
        applySessionIfPossible()
    }

    func configureLiveAppGraphIfNeeded() {
        guard arGuideViewModel == nil else { return }

        let parser: MusicXMLParserProtocol = MusicXMLParser()
        let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
        let practicePreparationService: PracticePreparationServiceProtocol =
            PracticePreparationService(parser: parser, stepBuilder: stepBuilder)
        let songLibraryIndexStore: SongLibraryIndexStoreProtocol = SongLibraryIndexStore()
        let songFileStore: SongFileStoreProtocol = SongFileStore()
        let audioImportService: AudioImportServiceProtocol = AudioImportService()
        let songLibraryPaths = SongLibraryPaths()
        let bundledSongLibraryProvider: BundledSongLibraryProviderProtocol = BundledSongLibraryProvider()
        let songAudioPlayer: SongAudioPlayerProtocol = SongAudioPlayer()
        let progressRepository: any PracticeProgressRepositoryProtocol = FilePracticeProgressRepository()
        let progressCoordinator = PracticeProgressCoordinator(repository: progressRepository)
        let diagnosticsStore: any DiagnosticsStoreProtocol = FileDiagnosticsStore()
        let diagnosticsReporter: any DiagnosticsReporting = AppDiagnosticsReporter(exportStore: diagnosticsStore)
        let diagnosticsExporter: any DiagnosticsArchiveExporting = DiagnosticsArchiveExporter(store: diagnosticsStore)
        let diagnosticsViewModel = DiagnosticsViewModel(
            store: diagnosticsStore,
            exporter: diagnosticsExporter
        )

        let makePressDetectionService: () -> PressDetectionServiceProtocol = { PressDetectionService() }
        let makeChordAttemptAccumulator: () -> ChordAttemptAccumulatorProtocol = { ChordAttemptAccumulator() }
        let makeSleeper: () -> SleeperProtocol = { TaskSleeper() }
        let makeLocalSamplerPlaybackService: () -> PracticeSequencerPlaybackServiceProtocol = {
            AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
        }
        let aiPlaybackServiceFactory = DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: {
                AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2", channel: 1)
            },
            makeExternalMIDIPlaybackService: { destinationUniqueID in
                CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID, channel: 1)
            }
        )
        let makeAIPlaybackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory = { aiPlaybackServiceFactory }
        let makeAudioStepAttemptAccumulator: () -> AudioStepAttemptAccumulator = {
            AudioStepAttemptAccumulator()
        }
        let makeHandPianoActivityGate: () -> HandPianoActivityGate = {
            HandPianoActivityGate()
        }
        let makeAudioRecognitionService: () -> PracticeAudioRecognitionServiceProtocol? = {
            #if targetEnvironment(simulator)
                nil
            #else
                PracticeAudioRecognitionService()
            #endif
        }
        let makeBluetoothMIDIEventSource: () -> PracticeInputEventSourceProtocol = {
            BluetoothMIDIInputEventSourceService()
        }

        let registry: PianoModeRegistryProtocol = PianoModeRegistryService(modes: PianoModeCatalogService.makeDefaultModes())
        pianoModeRegistry = registry

        let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel = { pianoModeID in
            switch PianoModeID(rawValue: pianoModeID ?? "") {
            case .bluetoothMIDI:
                let settingsProvider = UserDefaultsPracticeSessionSettingsProvider()
                let routing = settingsProvider.soundRoutingSettings
                let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol = switch routing.outputRoute {
                case .localSampler:
                    makeLocalSamplerPlaybackService()
                case .externalMIDIDestination:
                    if let destinationUniqueID = routing.midiDestinationUniqueID {
                        CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID)
                    } else {
                        makeLocalSamplerPlaybackService()
                    }
                }

                return PracticeSessionViewModel(
                    pressDetectionService: makePressDetectionService(),
                    chordAttemptAccumulator: makeChordAttemptAccumulator(),
                    sleeper: makeSleeper(),
                    sequencerPlaybackService: sequencerPlaybackService,
                    audioRecognitionService: nil,
                    practiceInputEventSource: makeBluetoothMIDIEventSource(),
                    audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                    handPianoActivityGate: makeHandPianoActivityGate(),
                    settingsProvider: settingsProvider,
                    progressCoordinator: progressCoordinator
                )

            case .virtualPiano:
                return PracticeSessionViewModel(
                    pressDetectionService: makePressDetectionService(),
                    chordAttemptAccumulator: makeChordAttemptAccumulator(),
                    sleeper: makeSleeper(),
                    sequencerPlaybackService: makeLocalSamplerPlaybackService(),
                    audioRecognitionService: nil,
                    practiceInputEventSource: nil,
                    audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                    handPianoActivityGate: makeHandPianoActivityGate(),
                    progressCoordinator: progressCoordinator
                )

            default:
                return PracticeSessionViewModel(
                    pressDetectionService: makePressDetectionService(),
                    chordAttemptAccumulator: makeChordAttemptAccumulator(),
                    sleeper: makeSleeper(),
                    sequencerPlaybackService: makeLocalSamplerPlaybackService(),
                    audioRecognitionService: makeAudioRecognitionService(),
                    practiceInputEventSource: nil,
                    audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                    handPianoActivityGate: makeHandPianoActivityGate(),
                    progressCoordinator: progressCoordinator
                )
            }
        }

        loadStoredCalibrationIfPossible()

        let guideViewModel = ARGuideViewModel(
            appState: self,
            practiceSetupState: practiceSetupState,
            pianoModeRegistry: registry,
            makePracticeSessionViewModel: makePracticeSessionViewModel,
            aiPlaybackServiceFactory: makeAIPlaybackServiceFactory
        )

        let libraryViewModel = SongLibraryViewModel(
            appState: self,
            practicePreparationService: practicePreparationService,
            indexStore: songLibraryIndexStore,
            fileStore: songFileStore,
            audioImportService: audioImportService,
            paths: songLibraryPaths,
            bundledProvider: bundledSongLibraryProvider,
            audioPlayer: songAudioPlayer,
            practiceProgressRepository: progressRepository
        )

        arGuideViewModel = guideViewModel
        songLibraryViewModel = libraryViewModel
        practiceProgressRepository = progressRepository
        practiceProgressCoordinator = progressCoordinator
        self.diagnosticsReporter = diagnosticsReporter
        self.diagnosticsViewModel = diagnosticsViewModel
        windowState = WindowTransitionState(practiceSetupState: practiceSetupState, pianoModeRegistry: registry)

        Task {
            do {
                try await diagnosticsStore.cleanupExpiredLogs(referenceDate: .now)
            } catch {
                _ = await diagnosticsReporter.record(
                    DiagnosticEvent(
                        severity: .warning,
                        code: .diagnosticsRetentionCleanupFailed,
                        category: .diagnostics,
                        stage: "startupRetentionCleanup",
                        summary: "无法清理过期诊断日志",
                        reason: String(describing: error),
                        persistence: .systemOnly
                    )
                )
            }
        }
    }

    private func worldAnchorPoint(from anchor: WorldAnchor) -> SIMD3<Float> {
        let transform = anchor.originFromAnchorTransform
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
}
