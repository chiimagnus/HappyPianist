import Observation
import SwiftUI

struct StatusSectionView: View {
    @Bindable var viewModel: PianoKeyViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("MIDI", systemImage: "pianokeys")
                        .font(.headline)
                    Spacer()
                    Text(viewModel.connectionDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(viewModel.isListening ? "Stop" : "Start") {
                        viewModel.toggleListening()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh Sources") {
                        viewModel.refreshMIDISources()
                    }
                    .buttonStyle(.bordered)

                    if !viewModel.hasAccessibilityPermission {
                        Button("Grant Permission") {
                            viewModel.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status: \(viewModel.statusMessage)")
                    Text("Sources: \(sourceNamesText)")
                    Text("MIDI Events: \(viewModel.midiEventCount)")
                    Text("Pressed: \(pressedNotesText)")
                    Text("Preview: \(viewModel.previewText)")
                        .lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } label: {
            Text("Runtime")
        }
    }

    private var pressedNotesText: String {
        guard !viewModel.pressedNotes.isEmpty else { return "-" }
        return viewModel.pressedNotes.map { MIDINote($0).name }.joined(separator: " ")
    }

    private var sourceNamesText: String {
        guard !viewModel.connectedSourceNames.isEmpty else { return "-" }
        return viewModel.connectedSourceNames.joined(separator: ", ")
    }
}

