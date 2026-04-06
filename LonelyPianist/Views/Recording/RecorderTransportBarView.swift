import Observation
import SwiftUI
import UniformTypeIdentifiers

struct RecorderTransportBarView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    @State private var renamingTakeID: UUID?
    @State private var renameDraft = ""
    @State private var isScrubbing = false
    @State private var isImportingMIDI = false
    @State private var importMode: LonelyPianistViewModel.MIDIImportMode = .all

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
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

                Spacer(minLength: 0)

                Picker(
                    selection: playbackOutputBinding,
                    label: Label("Output", systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                ) {
                    ForEach(viewModel.playbackOutputs) { output in
                        Text(output.title).tag(output.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.recorderMode == .playing || viewModel.playbackOutputs.isEmpty)

                Button {
                    viewModel.refreshPlaybackOutputs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh MIDI outputs")
                .disabled(viewModel.recorderMode == .playing)

                Picker(
                    selection: selectionBinding,
                    label: Label("Library", systemImage: "tray.full")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                ) {
                    if viewModel.takes.isEmpty {
                        Text("No takes").tag(Optional<UUID>.none)
                    } else {
                        ForEach(viewModel.takes) { take in
                            Text(take.name).tag(Optional(take.id))
                        }
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.takes.isEmpty)

                Menu {
                    Button("Import MIDI...") {
                        importMode = .all
                        isImportingMIDI = true
                    }
                    .disabled(viewModel.recorderMode != .idle)

                    Button("Import MIDI (Piano Only)...") {
                        importMode = .pianoOnly
                        isImportingMIDI = true
                    }
                    .disabled(viewModel.recorderMode != .idle)

                    Divider()

                    if let selectedTake = viewModel.selectedTake {
                        Button("Rename") {
                            renamingTakeID = selectedTake.id
                            renameDraft = selectedTake.name
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            viewModel.deleteTake(selectedTake.id)
                        }
                    } else {
                        Text("No take selected")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .disabled(viewModel.selectedTake == nil)

                Text(modeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(durationText)
                    .font(.system(.body, design: .monospaced))
            }

            Slider(
                value: playheadBinding,
                in: 0...(viewModel.selectedTake?.durationSec ?? 0)
            ) { isEditing in
                isScrubbing = isEditing
            }
            .disabled(viewModel.selectedTake == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .alert("Rename Take", isPresented: renameAlertBinding) {
            TextField("Take name", text: $renameDraft)
            Button("Save") {
                guard let renamingTakeID else { return }
                viewModel.renameTake(renamingTakeID, to: renameDraft)
                self.renamingTakeID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingTakeID = nil
            }
        }
        .fileImporter(
            isPresented: $isImportingMIDI,
            allowedContentTypes: [.midi]
        ) { result in
            switch result {
            case .success(let url):
                viewModel.importMIDIFile(from: url, mode: importMode)
            case .failure:
                break
            }
        }
    }

    private var playheadBinding: Binding<Double> {
        Binding(
            get: { viewModel.playheadSec },
            set: { newValue in
                let seconds = TimeInterval(newValue)
                if isScrubbing {
                    viewModel.seekPlayback(to: seconds)
                } else {
                    viewModel.playheadSec = seconds
                }
            }
        )
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingTakeID != nil },
            set: { isPresented in
                if !isPresented {
                    renamingTakeID = nil
                }
            }
        )
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedTakeID },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectTake(newValue)
            }
        )
    }

    private var playbackOutputBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedPlaybackOutputID },
            set: { newValue in
                viewModel.setPlaybackOutput(id: newValue)
            }
        )
    }

    private var modeText: String {
        switch viewModel.recorderMode {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .playing:
            return "Playing"
        }
    }

    private var durationText: String {
        let total = Int(viewModel.selectedTake?.durationSec ?? 0)
        let current = Int(viewModel.playheadSec)
        return "\(format(seconds: current)) / \(format(seconds: total))"
    }

    private func format(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}
