import AppKit
import MenuBarDockKit
import Observation
import SwiftUI

struct MenuBarMenuContentView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(viewModel.connectionDescription)
        Text(viewModel.statusMessage)
            .foregroundStyle(.secondary)

        Divider()

        Button(viewModel.isListening ? "Stop Listening" : "Start Listening") {
            viewModel.toggleListening()
        }

        Button("Refresh MIDI Sources") {
            viewModel.refreshMIDISources()
        }

        if !viewModel.hasAccessibilityPermission {
            Button("Grant Accessibility Permission") {
                viewModel.requestAccessibilityPermission()
            }
        }

        Divider()

        Button {
            viewModel.startRecordingTake()
        } label: {
            Label("Rec", systemImage: "record.circle")
        }
        .disabled(!viewModel.canRecord)

        Button {
            viewModel.playSelectedTake()
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        .disabled(!viewModel.canPlay)

        Button {
            viewModel.stopTransport()
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(!viewModel.canStop)

        Divider()

        Button("Open LonelyPianist") {
            DockPresenceService.prepareForPresentingMainWindow()
            openWindow(id: "main")
        }

        Button("Settings") {
            viewModel.selectedMainWindowSection = .settings
            DockPresenceService.prepareForPresentingMainWindow()
            openWindow(id: "main")
        }

        Divider()

        Button("Quit LonelyPianist") {
            NSApplication.shared.terminate(nil)
        }
    }
}
