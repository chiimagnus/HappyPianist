import SwiftData
import SwiftUI

@main
@MainActor
struct LonelyPianistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var viewModel: LonelyPianistViewModel

    init() {
        UserDefaults.standard.register(defaults: [
            DialoguePlaybackInterruptionBehavior.userDefaultsKey: DialoguePlaybackInterruptionBehavior.interrupt
                .rawValue,
        ])

        do {
            modelContainer = try ModelContainerFactory.makeMainContainer()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        let repository = SwiftDataMappingConfigRepository(context: modelContainer.mainContext)
        let recordingRepository = SwiftDataRecordingTakeRepository(context: modelContainer.mainContext)
        let midiOutputService = CoreMIDIOutputService()
        let playbackService = RoutedMIDIPlaybackService(
            samplerPlayback: AVSamplerMIDIPlaybackService(),
            midiOutPlayback: CoreMIDIOutputMIDIPlaybackService(outputService: midiOutputService),
            outputService: midiOutputService
        )

        let clock = SystemClock()
        let silenceDetectionService = DefaultSilenceDetectionService(clock: clock)
        let dialogueService = WebSocketDialogueService()
        let dialogueManager = DialogueManager(
            clock: clock,
            silenceDetectionService: silenceDetectionService,
            dialogueService: dialogueService,
            recordingRepository: recordingRepository,
            playbackService: playbackService
        )

        let viewModel = LonelyPianistViewModel(
            midiInputService: CoreMIDIInputService(),
            keyboardEventService: KeyboardEventService(),
            permissionService: AccessibilityPermissionService(),
            repository: repository,
            recordingRepository: recordingRepository,
            recordingService: DefaultRecordingService(clock: clock),
            playbackService: playbackService,
            mappingEngine: DefaultMappingEngine(),
            shortcutService: ShortcutExecutionService(),
            dialogueManager: dialogueManager
        )

        viewModel.bootstrap()
        AppContext.shared.viewModel = viewModel

        _viewModel = State(initialValue: viewModel)
    }

    var body: some Scene {
        Window("", id: "main") {
            MainWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 960, height: 640)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
