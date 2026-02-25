import AppKit
import MenuBarDockKit
import SwiftData
import SwiftUI

@main
@MainActor
struct PianoKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer
    @State private var viewModel: PianoKeyViewModel

    init() {
        // Default to "menu bar only" to keep PianoKey as a menu bar tool app.
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
        let viewModel = PianoKeyViewModel(
            midiInputService: CoreMIDIInputService(),
            keyboardEventService: KeyboardEventService(),
            permissionService: AccessibilityPermissionService(),
            repository: repository,
            recordingRepository: recordingRepository,
            recordingService: DefaultRecordingService(clock: SystemClock()),
            playbackService: AVSamplerMIDIPlaybackService(),
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
    }
}
