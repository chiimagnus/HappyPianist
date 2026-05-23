import Observation
import SwiftUI
import UniformTypeIdentifiers

struct RecorderPanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    @State private var renamingTakeID: UUID?
    @State private var renameDraft = ""
    @State private var isImportingMIDI = false
    @State private var importMode: LonelyPianistViewModel.MIDIImportMode = .all

    var body: some View {
        VStack(spacing: 0) {
            PianoRollView(take: viewModel.displayedTake, playheadSec: viewModel.playheadSec)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            RecorderStatusBarView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
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

                Picker(
                    selection: playbackOutputBinding,
                    label: Label("Output", systemImage: "speaker.wave.2")
                ) {
                    ForEach(viewModel.playbackOutputs) { output in
                        Text(output.title).tag(output.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.recorderMode == .playing || viewModel.playbackOutputs.isEmpty)

                Picker(
                    selection: selectionBinding,
                    label: Label("Library", systemImage: "tray.full")
                ) {
                    if viewModel.takes.isEmpty {
                        Text("No takes").tag(UUID?.none)
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
                }
                .disabled(viewModel.selectedTake == nil)

                Button {
                    Task { @MainActor in
                        await viewModel.bluetoothMIDI.openBluetoothMIDIWindow()
                    }
                } label: {
                    Label("Bluetooth MIDI…", systemImage: "dot.radiowaves.left.and.right")
                }
            }
        }
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
            case let .success(url):
                viewModel.importMIDIFile(from: url, mode: importMode)
            case .failure:
                break
            }
        }
        .alert(item: bluetoothAlertBinding) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: .default(Text(alert.primaryButtonTitle)) {
                    viewModel.bluetoothMIDI.performPrimaryAction(alert.primaryAction)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var bluetoothAlertBinding: Binding<BluetoothMIDIViewModel.AlertInfo?> {
        Binding(
            get: { viewModel.bluetoothMIDI.alert },
            set: { newValue in
                if newValue == nil {
                    viewModel.bluetoothMIDI.dismissAlert()
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
}
