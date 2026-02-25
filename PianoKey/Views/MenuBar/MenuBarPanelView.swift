import AppKit
import MenuBarDockKit
import Observation
import SwiftUI

struct MenuBarPanelView: View {
    @Bindable var viewModel: PianoKeyViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionDescription)
                    .font(.headline)
            }

            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(viewModel.isListening ? "Stop Listening" : "Start Listening") {
                viewModel.toggleListening()
            }
            .buttonStyle(.borderedProminent)

            Button("Refresh MIDI Sources") {
                viewModel.refreshMIDISources()
            }
            .buttonStyle(.bordered)

            if !viewModel.hasAccessibilityPermission {
                Button("Grant Accessibility Permission") {
                    viewModel.requestAccessibilityPermission()
                }
                .buttonStyle(.bordered)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    viewModel.startRecordingTake()
                } label: {
                    Label("Rec", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!viewModel.canRecord)

                Button {
                    viewModel.playSelectedTake()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canPlay)

                Button {
                    viewModel.stopTransport()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)
            }

            Divider()

            Button("Open PianoKey") {
                DockPresenceService.prepareForPresentingMainWindow()
                openWindow(id: "main")
            }
            .buttonStyle(.bordered)

            Button("Settings") {
                viewModel.selectedMainWindowSection = .settings
                DockPresenceService.prepareForPresentingMainWindow()
                openWindow(id: "main")
            }
            .buttonStyle(.bordered)

            Button("Quit PianoKey") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected(let sourceCount):
            return sourceCount > 0 ? .green : .yellow
        case .failed:
            return .red
        case .idle:
            return .gray
        }
    }
}
