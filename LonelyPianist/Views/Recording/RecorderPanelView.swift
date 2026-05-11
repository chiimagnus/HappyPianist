import CoreAudioKit
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct RecorderPanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    @State private var renamingTakeID: UUID?
    @State private var renameDraft = ""
    @State private var isImportingMIDI = false
    @State private var importMode: LonelyPianistViewModel.MIDIImportMode = .all
    @State private var bluetoothMIDIWindowController: CABTLEMIDIWindowController?
    @State private var bluetoothPreflight = BluetoothAccessPreflight()
    @State private var bluetoothAlert: BluetoothAlert?

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
                    openBluetoothMIDIWindow()
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
        .alert(item: $bluetoothAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                primaryButton: alert.primaryButton,
                secondaryButton: .cancel()
            )
        }
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

    private func openBluetoothMIDIWindow() {
        Task { @MainActor in
            let status = await bluetoothPreflight.checkOrRequestAccess()
            switch status {
                case .ready:
                    let controller = bluetoothMIDIWindowController ?? CABTLEMIDIWindowController()
                    bluetoothMIDIWindowController = controller
                    controller.showWindow(nil)
                    controller.window?.makeKeyAndOrderFront(nil)

                case .bluetoothPoweredOff:
                    bluetoothAlert = .bluetoothOff

                case .unauthorized:
                    bluetoothAlert = .unauthorized

                case .unsupported:
                    bluetoothAlert = .unsupported

                case .unknown:
                    bluetoothAlert = .unknown
            }
        }
    }
}

private struct BluetoothAlert: Identifiable {
    enum Kind {
        case unauthorized
        case bluetoothOff
        case unsupported
        case unknown
    }

    let id = UUID()
    let kind: Kind

    var title: String {
        switch kind {
            case .unauthorized:
                "Bluetooth Permission Needed"
            case .bluetoothOff:
                "Bluetooth Is Off"
            case .unsupported:
                "Bluetooth Not Supported"
            case .unknown:
                "Bluetooth Unavailable"
        }
    }

    var message: String {
        switch kind {
            case .unauthorized:
                "请在 System Settings → Privacy & Security → Bluetooth 中允许 LonelyPianist 访问蓝牙，然后再重试。"
            case .bluetoothOff:
                "请先在系统中打开蓝牙，然后再连接 Bluetooth MIDI。"
            case .unsupported:
                "当前设备不支持蓝牙，无法使用 Bluetooth MIDI。"
            case .unknown:
                "系统蓝牙状态暂不可用。请稍后重试，或重启蓝牙后再试。"
        }
    }

    var primaryButton: Alert.Button {
        switch kind {
            case .unauthorized:
                .default(Text("Open Settings")) {
                    openBluetoothPrivacySettings()
                }
            case .bluetoothOff:
                .default(Text("Open Bluetooth Settings")) {
                    openBluetoothSettings()
                }
            case .unsupported, .unknown:
                .default(Text("OK")) {}
        }
    }

    static let unauthorized = BluetoothAlert(kind: .unauthorized)
    static let bluetoothOff = BluetoothAlert(kind: .bluetoothOff)
    static let unsupported = BluetoothAlert(kind: .unsupported)
    static let unknown = BluetoothAlert(kind: .unknown)
}

private func openBluetoothPrivacySettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") else { return }
    NSWorkspace.shared.open(url)
}

private func openBluetoothSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") {
        NSWorkspace.shared.open(url)
    } else if let url = URL(string: "x-apple.systempreferences:") {
        NSWorkspace.shared.open(url)
    }
}
