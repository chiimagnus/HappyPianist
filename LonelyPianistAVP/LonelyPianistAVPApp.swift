import SwiftUI

@main
struct LonelyPianistAVPApp: App {
    @State private var appState: AppState
    @State private var arGuideViewModel: ARGuideViewModel
    @State private var flowState: FlowState
    @State private var coordinator: WindowCoordinator
    @State private var songLibraryViewModel: SongLibraryViewModel

    init() {
        // --- Independent services ---
        let worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol = WorldAnchorCalibrationStore()
        let keyGeometryService: PianoKeyGeometryServiceProtocol = PianoKeyGeometryService()
        let parser: MusicXMLParserProtocol = MusicXMLParser()
        let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
        let arTrackingService: ARTrackingServiceProtocol = ARTrackingService()
        let calibrationCaptureService = CalibrationPointCaptureService()
        let songLibraryIndexStore: SongLibraryIndexStoreProtocol = SongLibraryIndexStore()
        let songFileStore: SongFileStoreProtocol = SongFileStore()
        let audioImportService: AudioImportServiceProtocol = AudioImportService()
        let songLibraryPaths = SongLibraryPaths()
        let bundledSongLibraryProvider: BundledSongLibraryProviderProtocol = BundledSongLibraryProvider()
        let songAudioPlayer: SongAudioPlayerProtocol = SongAudioPlayer()

        // --- Dependent services ---
        let practicePreparationService: PracticePreparationServiceProtocol =
            PracticePreparationService(parser: parser, stepBuilder: stepBuilder)
        let calibrationRepository: CalibrationRepositoryProtocol =
            CalibrationRepository(worldAnchorCalibrationStore: worldAnchorCalibrationStore)

        // --- PracticeSessionViewModel factory closures ---
        let makePressDetectionService: () -> PressDetectionServiceProtocol = {
            PressDetectionService()
        }
        let makeChordAttemptAccumulator: () -> ChordAttemptAccumulatorProtocol = {
            ChordAttemptAccumulator()
        }
        let makeSleeper: () -> SleeperProtocol = {
            TaskSleeper()
        }
        let makeSequencerPlaybackService: () -> PracticeSequencerPlaybackServiceProtocol = {
            AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
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

        // --- PianoModeRegistry ---
        let pianoModeRegistry: PianoModeRegistryProtocol = PianoModeRegistryService(modes: [
            RealAudioPianoMode(makePracticeSessionViewModel: {
                PracticeSessionViewModel(
                    pressDetectionService: makePressDetectionService(),
                    chordAttemptAccumulator: makeChordAttemptAccumulator(),
                    sleeper: makeSleeper(),
                    sequencerPlaybackService: makeSequencerPlaybackService(),
                    audioRecognitionService: makeAudioRecognitionService(),
                    practiceInputEventSource: nil,
                    audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                    handPianoActivityGate: makeHandPianoActivityGate()
                )
            }),
            BluetoothMIDIPianoMode(makePracticeSessionViewModel: {
                PracticeSessionViewModel(
                    pressDetectionService: makePressDetectionService(),
                    chordAttemptAccumulator: makeChordAttemptAccumulator(),
                    sleeper: makeSleeper(),
                    sequencerPlaybackService: makeSequencerPlaybackService(),
                    audioRecognitionService: nil,
                    practiceInputEventSource: makeBluetoothMIDIEventSource(),
                    audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                    handPianoActivityGate: makeHandPianoActivityGate()
                )
            }),
            VirtualPianoMode(makePracticeSessionViewModel: {
                PracticeSessionViewModel(
                    pressDetectionService: makePressDetectionService(),
                    chordAttemptAccumulator: makeChordAttemptAccumulator(),
                    sleeper: makeSleeper(),
                    sequencerPlaybackService: makeSequencerPlaybackService(),
                    audioRecognitionService: nil,
                    practiceInputEventSource: nil,
                    audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                    handPianoActivityGate: makeHandPianoActivityGate()
                )
            }),
        ])

        // --- PracticeSessionViewModelFactory ---
        let practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol =
            PracticeSessionViewModelFactoryService(
                pianoModeRegistry: pianoModeRegistry,
                makeFallbackPracticeSessionViewModel: {
                    PracticeSessionViewModel(
                        pressDetectionService: makePressDetectionService(),
                        chordAttemptAccumulator: makeChordAttemptAccumulator(),
                        sleeper: makeSleeper(),
                        sequencerPlaybackService: makeSequencerPlaybackService(),
                        audioRecognitionService: makeAudioRecognitionService(),
                        practiceInputEventSource: nil,
                        audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                        handPianoActivityGate: makeHandPianoActivityGate()
                    )
                }
            )

        // --- App-level state ---
        let appState = AppState(
            arTrackingService: arTrackingService,
            calibrationCaptureService: calibrationCaptureService,
            calibrationRepository: calibrationRepository,
            keyGeometryService: keyGeometryService
        )
        appState.loadStoredCalibrationIfPossible()

        let flowState = FlowState()

        let arGuideViewModel = ARGuideViewModel(
            appState: appState,
            flowState: flowState,
            pianoModeRegistry: pianoModeRegistry,
            practiceSessionViewModelFactory: practiceSessionViewModelFactory
        )

        let songLibraryViewModel = SongLibraryViewModel(
            appState: appState,
            flowState: flowState,
            practicePreparationService: practicePreparationService,
            indexStore: songLibraryIndexStore,
            fileStore: songFileStore,
            audioImportService: audioImportService,
            paths: songLibraryPaths,
            bundledProvider: bundledSongLibraryProvider,
            audioPlayer: songAudioPlayer
        )

        // --- Store as @State ---
        _appState = State(initialValue: appState)
        _arGuideViewModel = State(initialValue: arGuideViewModel)
        _flowState = State(initialValue: flowState)
        _songLibraryViewModel = State(initialValue: songLibraryViewModel)
        _coordinator = State(initialValue: WindowCoordinator(
            flowState: flowState,
            pianoModeRegistry: pianoModeRegistry
        ))
    }

    var body: some Scene {
        Window("Preparation", id: WindowIDs.preparation) {
            PreparationWindowRootView(arGuideViewModel: arGuideViewModel)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowIDs.preparation, context: context)
        }

        Window("Library", id: WindowIDs.library) {
            LibraryWindowRootView(appState: appState, songLibraryViewModel: songLibraryViewModel)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowIDs.library, context: context)
        }

        Window("Practice", id: WindowIDs.practice) {
            PracticeWindowRootView(viewModel: arGuideViewModel)
                .environment(coordinator)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in
            makeReplacementPlacementIfPossible(targetWindowID: WindowIDs.practice, context: context)
        }

        ImmersiveSpace(id: appState.immersiveSpaceID) {
            ImmersiveView(viewModel: arGuideViewModel)
                .onAppear {
                    appState.immersiveSpaceState = .open
                }
                .onDisappear {
                    appState.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    private func makeReplacementPlacementIfPossible(
        targetWindowID: String,
        context: WindowPlacementContext
    ) -> WindowPlacement {
        guard let pendingTransition = coordinator.pendingTransition else { return WindowPlacement() }
        guard pendingTransition.toWindowID == targetWindowID else { return WindowPlacement() }

        guard let sourceWindow = context.windows.first(where: { $0.id == pendingTransition.fromWindowID }) else {
            return WindowPlacement()
        }

        return WindowPlacement(.replacing(sourceWindow))
    }
}
