import Observation
import SwiftUI
import AppKit

struct BluetoothMIDIPanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            scanControls

            Divider()

            peripheralsList

            Divider()

            debugPanel

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bluetooth MIDI")
                .font(.title2.weight(.semibold))

            Text("State: \(stateDescription)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("CoreMIDI: sources \(snapshot.coreMIDISourceCount), destinations \(snapshot.coreMIDIDestinationCount)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("App connected MIDI input sources: \(viewModel.connectedSourceNames.count)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Refresh MIDI Sources") {
                viewModel.refreshMIDISources()
            }
        }
    }

    private var scanControls: some View {
        HStack(spacing: 12) {
            Toggle(
                "Remember Last Device",
                isOn: Binding(
                    get: { viewModel.rememberLastBluetoothMIDIDevice },
                    set: { viewModel.setRememberLastBluetoothMIDIDevice($0) }
                )
            )
            .toggleStyle(.switch)

            Picker("Scan Mode", selection: $viewModel.bluetoothMIDIScanMode) {
                Text("MIDI Service Filtered").tag(BluetoothMIDIScanMode.midiServiceFiltered)
                Text("All Devices (Verify After Connect)").tag(BluetoothMIDIScanMode.allDevices)
            }
            .pickerStyle(.menu)

            Button(isScanning ? "Stop Scan" : "Start Scan") {
                isScanning ? viewModel.stopBluetoothMIDIScan() : viewModel.startBluetoothMIDIScan()
            }

            Spacer()
        }
        .onChange(of: viewModel.bluetoothMIDIScanMode) {
            guard isScanning else { return }
            viewModel.startBluetoothMIDIScan()
        }
    }

    private var peripheralsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovered (\(viewModel.bluetoothMIDIDiscoveredPeripherals.count))")
                .font(.headline)

            List {
                ForEach(viewModel.bluetoothMIDIDiscoveredPeripherals) { peripheral in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peripheral.name ?? "Unknown")
                                .font(.body.weight(.medium))
                            Text(peripheral.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let rssi = peripheral.rssi {
                            Text("RSSI \(rssi)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(peripheral.lastSeen, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Connect") {
                            viewModel.connectBluetoothMIDI(id: peripheral.id)
                        }
                        .disabled(!canConnect(peripheralID: peripheral.id))

                        Button("Disconnect") {
                            viewModel.disconnectBluetoothMIDI(id: peripheral.id)
                        }
                        .disabled(!canDisconnect(peripheralID: peripheral.id))
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 240)
        }
    }

    private var debugPanel: some View {
        return VStack(alignment: .leading, spacing: 8) {
            Text("Debug")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("CoreMIDI devices").foregroundStyle(.secondary)
                    Text("\(snapshot.coreMIDIDeviceCount)")
                }
                GridRow {
                    Text("CoreMIDI sources").foregroundStyle(.secondary)
                    Text("\(snapshot.coreMIDISourceCount)")
                }
                GridRow {
                    Text("CoreMIDI destinations").foregroundStyle(.secondary)
                    Text("\(snapshot.coreMIDIDestinationCount)")
                }
                GridRow {
                    Text("Central state").foregroundStyle(.secondary)
                    Text("\(snapshot.centralStateRawValue)")
                }
                GridRow {
                    Text("Authorization").foregroundStyle(.secondary)
                    Text(snapshot.authorization ?? "(nil)")
                }
                GridRow {
                    Text("Scanning").foregroundStyle(.secondary)
                    Text(snapshot.isScanning ? "Yes" : "No")
                }
                GridRow {
                    Text("Scan mode").foregroundStyle(.secondary)
                    Text(snapshot.scanMode)
                }
                GridRow {
                    Text("Target").foregroundStyle(.secondary)
                    Text(snapshot.targetPeripheralID ?? "(nil)")
                }
                GridRow {
                    Text("Last error").foregroundStyle(.secondary)
                    Text(snapshot.lastError ?? "(nil)")
                }
                GridRow {
                    Text("Activate status").foregroundStyle(.secondary)
                    Text(snapshot.lastActivationStatus.map(String.init) ?? "(nil)")
                }
                GridRow {
                    Text("Disconnect status").foregroundStyle(.secondary)
                    Text(snapshot.lastDisconnectStatus.map(String.init) ?? "(nil)")
                }
            }
            .font(.caption)

            HStack {
                Button("Copy Debug Snapshot") {
                    copyToClipboard(viewModel.bluetoothMIDIDebugSnapshotText())
                }

                Spacer()
            }
        }
    }

    private var snapshot: BluetoothMIDIDebugSnapshot {
        viewModel.bluetoothMIDIDebugSnapshot()
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var isScanning: Bool {
        if case .scanning = viewModel.bluetoothMIDIConnectionState {
            return true
        }
        return false
    }

    private var stateDescription: String {
        switch viewModel.bluetoothMIDIConnectionState {
            case .idle:
                "Idle"
            case let .scanning(mode):
                mode == .midiServiceFiltered ? "Scanning (filtered)" : "Scanning (all devices)"
            case .readyToConnect:
                "Ready to connect"
            case let .connecting(id):
                "Connecting \(id)"
            case let .verifying(id):
                "Verifying \(id)"
            case let .activating(id):
                "Activating \(id)"
            case let .activated(id):
                "Activated \(id)"
            case let .disconnecting(id):
                "Disconnecting \(id)"
            case let .failed(message):
                "Failed: \(message)"
            case .denied:
                "Denied"
            case .poweredOff:
                "Powered off"
            case .unsupported:
                "Unsupported"
        }
    }

    private func canConnect(peripheralID id: String) -> Bool {
        switch viewModel.bluetoothMIDIConnectionState {
            case .connecting, .verifying, .activating, .disconnecting:
                return false
            case .denied, .poweredOff, .unsupported:
                return false
            default:
                return true
        }
    }

    private func canDisconnect(peripheralID id: String) -> Bool {
        switch viewModel.bluetoothMIDIConnectionState {
            case let .activated(activeID),
                 let .connecting(activeID),
                 let .verifying(activeID),
                 let .activating(activeID),
                 let .disconnecting(activeID):
                return activeID == id
            default:
                return false
        }
    }
}
