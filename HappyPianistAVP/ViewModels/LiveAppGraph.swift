import Foundation

@MainActor
struct LiveAppGraph {
    let appState: AppState
    let windowState: WindowTransitionState
    let arGuideViewModel: ARGuideViewModel
    let songLibraryViewModel: SongLibraryViewModel
    let practiceLaunchViewModel: PracticeLaunchViewModel
    let practiceSessionRecorder: PracticeSessionRecorder
    let diagnosticsViewModel: DiagnosticsViewModel

    static func make() -> LiveAppGraph {
        let diagnosticsStore: any DiagnosticsStoreProtocol = FileDiagnosticsStore()
        let diagnosticsReporter: any DiagnosticsReporting = AppDiagnosticsReporter(
            exportStore: diagnosticsStore
        )
        let worldAnchorCalibrationStore = WorldAnchorCalibrationStore()
        let appState = AppState(
            arTrackingService: ARTrackingService(),
            calibrationCaptureService: CalibrationPointCaptureService(),
            calibrationRepository: CalibrationRepository(
                worldAnchorCalibrationStore: worldAnchorCalibrationStore,
                diagnosticsReporter: diagnosticsReporter
            ),
            keyGeometryService: PianoKeyGeometryService()
        )
        let parser: MusicXMLParserProtocol = MusicXMLParser()
        let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
        let practicePreparationService: PracticePreparationServiceProtocol =
            PracticePreparationService(parser: parser, stepBuilder: stepBuilder)
        let songLibraryIndexStore = SongLibraryIndexStore()
        let songFileStore: SongFileStoreProtocol = SongFileStore()
        let audioImportService: AudioImportServiceProtocol = AudioImportService()
        let bundledSongLibraryProvider: BundledSongLibraryProviderProtocol =
            BundledSongLibraryProvider()
        let songLibraryEntryResolver: any SongLibraryEntryResolving = SongLibraryEntryResolver(
            indexStore: songLibraryIndexStore,
            bundledProvider: bundledSongLibraryProvider,
            fileStore: songFileStore
        )
        let songAudioPlayer: SongAudioPlayerProtocol = SongAudioPlayer()
        let progressRepository = FilePracticeProgressRepository()
        let progressCoordinator = PracticeProgressCoordinator(
            repository: progressRepository,
            diagnosticsReporter: diagnosticsReporter
        )
        let diagnosticsExporter: any DiagnosticsArchiveExporting = DiagnosticsArchiveExporter(
            store: diagnosticsStore
        )
        let diagnosticsViewModel = DiagnosticsViewModel(
            store: diagnosticsStore,
            exporter: diagnosticsExporter
        )
        let practiceSessionRecorder = PracticeSessionRecorder(
            repository: progressRepository,
            diagnosticsReporter: diagnosticsReporter
        )
        let importTransactionService = SongLibraryImportTransactionService(
            indexStore: songLibraryIndexStore,
            diagnostics: diagnosticsReporter
        )

        let makePressDetectionService: () -> PressDetectionServiceProtocol = { PressDetectionService() }
        let makeChordAttemptAccumulator: () -> ChordAttemptAccumulatorProtocol = {
            ChordAttemptAccumulator()
        }
        let makeSleeper: () -> SleeperProtocol = { TaskSleeper() }
        let makeLocalSamplerPlaybackService: () -> PracticeSequencerPlaybackServiceProtocol = {
            AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
        }
        let aiPlaybackServiceFactory = DuetAIPlaybackServiceFactory(
            makeLocalSamplerPlaybackService: {
                AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2", channel: 1)
            },
            makeExternalMIDIPlaybackService: { destinationUniqueID in
                CoreMIDIPracticePlaybackService(
                    destinationUniqueID: destinationUniqueID,
                    diagnosticsReporter: diagnosticsReporter,
                    channel: 1
                )
            }
        )
        let makeAIPlaybackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory = {
            aiPlaybackServiceFactory
        }
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
                PracticeAudioRecognitionService(diagnosticsReporter: diagnosticsReporter)
            #endif
        }
        let makeBluetoothMIDIEventSource: () -> PracticeInputEventSourceProtocol = {
            BluetoothMIDIInputEventSourceService(diagnosticsReporter: diagnosticsReporter)
        }

        let registry: PianoModeRegistryProtocol = PianoModeRegistryService(
            modes: PianoModeCatalogService.makeDefaultModes()
        )
        let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel = {
            pianoModeID in
            switch PianoModeID(rawValue: pianoModeID ?? "") {
            case .bluetoothMIDI:
                let settingsProvider = UserDefaultsPracticeSessionSettingsProvider()
                let routing = settingsProvider.soundRoutingSettings
                let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol =
                    switch routing.outputRoute {
                    case .localSampler:
                        makeLocalSamplerPlaybackService()
                    case .externalMIDIDestination:
                        if let destinationUniqueID = routing.midiDestinationUniqueID {
                            CoreMIDIPracticePlaybackService(
                                destinationUniqueID: destinationUniqueID,
                                diagnosticsReporter: diagnosticsReporter
                            )
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
                    progressCoordinator: progressCoordinator,
                    sessionRecorder: practiceSessionRecorder,
                    diagnosticsReporter: diagnosticsReporter
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
                    progressCoordinator: progressCoordinator,
                    sessionRecorder: practiceSessionRecorder,
                    diagnosticsReporter: diagnosticsReporter
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
                    progressCoordinator: progressCoordinator,
                    sessionRecorder: practiceSessionRecorder,
                    diagnosticsReporter: diagnosticsReporter
                )
            }
        }

        appState.loadStoredCalibrationIfPossible()
        let arGuideViewModel = ARGuideViewModel(
            appState: appState,
            practiceSetupState: appState.practiceSetupState,
            pianoModeRegistry: registry,
            makePracticeSessionViewModel: makePracticeSessionViewModel,
            aiPlaybackServiceFactory: makeAIPlaybackServiceFactory,
            diagnosticsReporter: diagnosticsReporter
        )
        let songLibraryViewModel = SongLibraryViewModel(
            indexStore: songLibraryIndexStore,
            importTransactionService: importTransactionService,
            fileStore: songFileStore,
            audioImportService: audioImportService,
            bundledProvider: bundledSongLibraryProvider,
            audioPlayer: songAudioPlayer,
            practiceProgressRepository: progressRepository,
            practiceProgressRecovery: progressRepository,
            diagnosticsReporter: diagnosticsReporter,
            snapshotBuilder: SongPracticeLibrarySnapshotBuilder(),
            bootstrapLoader: LiveSongLibraryBootstrapLoader(
                transactionRecovery: importTransactionService,
                indexStore: songLibraryIndexStore,
                bundledProvider: bundledSongLibraryProvider
            )
        )
        let practiceLaunchViewModel = PracticeLaunchViewModel(
            resolver: songLibraryEntryResolver,
            preparationService: practicePreparationService,
            applicator: arGuideViewModel,
            diagnosticsReporter: diagnosticsReporter,
            progressRepository: progressRepository,
            progressRecovery: progressRepository,
            sessionRecorder: practiceSessionRecorder
        )
        let windowState = WindowTransitionState(
            practiceSetupState: appState.practiceSetupState,
            pianoModeRegistry: registry
        )

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

        return LiveAppGraph(
            appState: appState,
            windowState: windowState,
            arGuideViewModel: arGuideViewModel,
            songLibraryViewModel: songLibraryViewModel,
            practiceLaunchViewModel: practiceLaunchViewModel,
            practiceSessionRecorder: practiceSessionRecorder,
            diagnosticsViewModel: diagnosticsViewModel
        )
    }
}
