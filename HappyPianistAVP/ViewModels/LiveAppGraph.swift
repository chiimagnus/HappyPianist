import Foundation

@MainActor
struct LiveAppGraph {
  let appState: AppState
  let windowState: WindowTransitionState
  let arGuideViewModel: ARGuideViewModel
  let songLibraryViewModel: SongLibraryViewModel
  let diagnosticsViewModel: DiagnosticsViewModel

  static func make() -> LiveAppGraph {
    let worldAnchorCalibrationStore = WorldAnchorCalibrationStore()
    let appState = AppState(
      arTrackingService: ARTrackingService(),
      calibrationCaptureService: CalibrationPointCaptureService(),
      calibrationRepository: CalibrationRepository(
        worldAnchorCalibrationStore: worldAnchorCalibrationStore
      ),
      keyGeometryService: PianoKeyGeometryService()
    )
    let parser: MusicXMLParserProtocol = MusicXMLParser()
    let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
    let practicePreparationService: PracticePreparationServiceProtocol =
      PracticePreparationService(parser: parser, stepBuilder: stepBuilder)
    let songLibraryIndexStore: SongLibraryIndexStoreProtocol = SongLibraryIndexStore()
    let songFileStore: SongFileStoreProtocol = SongFileStore()
    let audioImportService: AudioImportServiceProtocol = AudioImportService()
    let bundledSongLibraryProvider: BundledSongLibraryProviderProtocol =
      BundledSongLibraryProvider()
    let songAudioPlayer: SongAudioPlayerProtocol = SongAudioPlayer()
    let progressRepository: any PracticeProgressRepositoryProtocol =
      FilePracticeProgressRepository()
    let progressCoordinator = PracticeProgressCoordinator(repository: progressRepository)
    let diagnosticsStore: any DiagnosticsStoreProtocol = FileDiagnosticsStore()
    let diagnosticsReporter: any DiagnosticsReporting = AppDiagnosticsReporter(
      exportStore: diagnosticsStore)
    let diagnosticsExporter: any DiagnosticsArchiveExporting = DiagnosticsArchiveExporter(
      store: diagnosticsStore)
    let diagnosticsViewModel = DiagnosticsViewModel(
      store: diagnosticsStore,
      exporter: diagnosticsExporter
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
        CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID, channel: 1)
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
        PracticeAudioRecognitionService()
      #endif
    }
    let makeBluetoothMIDIEventSource: () -> PracticeInputEventSourceProtocol = {
      BluetoothMIDIInputEventSourceService()
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

    appState.loadStoredCalibrationIfPossible()
    let arGuideViewModel = ARGuideViewModel(
      appState: appState,
      practiceSetupState: appState.practiceSetupState,
      pianoModeRegistry: registry,
      makePracticeSessionViewModel: makePracticeSessionViewModel,
      aiPlaybackServiceFactory: makeAIPlaybackServiceFactory
    )
    let songLibraryViewModel = SongLibraryViewModel(
      arGuideViewModel: arGuideViewModel,
      practicePreparationService: practicePreparationService,
      indexStore: songLibraryIndexStore,
      fileStore: songFileStore,
      audioImportService: audioImportService,
      bundledProvider: bundledSongLibraryProvider,
      audioPlayer: songAudioPlayer,
      practiceProgressRepository: progressRepository,
      diagnosticsReporter: diagnosticsReporter,
      bootstrapLoader: LiveSongLibraryBootstrapLoader(
        indexStore: songLibraryIndexStore,
        bundledProvider: bundledSongLibraryProvider
      )
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
      diagnosticsViewModel: diagnosticsViewModel
    )
  }
}
