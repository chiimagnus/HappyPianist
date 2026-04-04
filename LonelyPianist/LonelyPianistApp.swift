import AppKit
import MenuBarDockKit
import SwiftData
import SwiftUI

@main
@MainActor
struct LonelyPianistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var viewModel: LonelyPianistViewModel
    @State private var menuBarExtraVisibilityStore = MenuBarExtraVisibilityStore()

    init() {
        // Default to "menu bar only" to keep LonelyPianist as a menu bar tool app.
        UserDefaults.standard.register(defaults: [
            AppIconDisplayMode.userDefaultsKey: AppIconDisplayMode.menuBarOnly.rawValue
        ])

        let schema = Schema([
            MappingProfileEntity.self,
            RecordingTakeEntity.self,
            RecordedNoteEntity.self
        ])

        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        let repository = SwiftDataMappingProfileRepository(context: modelContainer.mainContext)
        let recordingRepository = SwiftDataRecordingTakeRepository(context: modelContainer.mainContext)
        let midiOutputService = CoreMIDIOutputService()
        let playbackService = RoutedMIDIPlaybackService(
            samplerPlayback: AVSamplerMIDIPlaybackService(),
            midiOutPlayback: CoreMIDIOutputMIDIPlaybackService(outputService: midiOutputService),
            outputService: midiOutputService
        )
        let viewModel = LonelyPianistViewModel(
            midiInputService: CoreMIDIInputService(),
            keyboardEventService: KeyboardEventService(),
            permissionService: AccessibilityPermissionService(),
            repository: repository,
            recordingRepository: recordingRepository,
            recordingService: DefaultRecordingService(clock: SystemClock()),
            playbackService: playbackService,
            mappingEngine: DefaultMappingEngine(),
            shortcutService: ShortcutExecutionService()
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
        .commands {
            AppCommands()
        }

        MenuBarExtra(
            "LonelyPianist",
            systemImage: "pianokeys",
            isInserted: Binding(
                get: { menuBarExtraVisibilityStore.isInserted },
                set: { menuBarExtraVisibilityStore.isInserted = $0 }
            )
        ) {
            MenuBarMenuContentView(viewModel: viewModel)
        }
    }
}
