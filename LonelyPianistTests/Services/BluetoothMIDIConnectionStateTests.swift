import Foundation
@testable import LonelyPianist
import Testing

@MainActor
@Test
func startScanPublishesStateChange() {
    let service = BluetoothMIDIConnectionServiceMock()

    var received: [BluetoothMIDIConnectionState] = []
    service.onConnectionStateChange = { state in
        MainActor.assumeIsolated {
            received.append(state)
        }
    }

    service.startScan(mode: .midiServiceFiltered)

    #expect(service.startScanCalls == [.midiServiceFiltered])
    #expect(service.connectionState == .scanning(mode: .midiServiceFiltered))
    #expect(received.last == .scanning(mode: .midiServiceFiltered))
}

@MainActor
@Test
func setPeripheralsPublishesListChange() {
    let service = BluetoothMIDIConnectionServiceMock()

    var received: [[BluetoothMIDIPeripheral]] = []
    service.onPeripheralsChange = { peripherals in
        MainActor.assumeIsolated {
            received.append(peripherals)
        }
    }

    let peripheral = BluetoothMIDIPeripheral(id: "A", name: "Piano", rssi: -42, lastSeen: Date(timeIntervalSince1970: 1))
    service.setPeripherals([peripheral])

    #expect(service.discoveredPeripherals == [peripheral])
    #expect(received.last == [peripheral])
}

@MainActor
@Test
func debugSnapshotReflectsLatestState() {
    let service = BluetoothMIDIConnectionServiceMock()
    service.mockCentralStateRawValue = 4
    service.mockAuthorization = "allowedAlways"
    service.mockLastActivationStatus = 123
    service.mockLastDisconnectStatus = 0

    service.startScan(mode: .allDevices)
    service.connect(id: "DEVICE")
    service.setPeripherals([
        BluetoothMIDIPeripheral(id: "DEVICE", name: "Piano", rssi: -10, lastSeen: Date(timeIntervalSince1970: 1)),
    ])

    let snapshot = service.debugSnapshot
    #expect(snapshot.centralStateRawValue == 4)
    #expect(snapshot.authorization == "allowedAlways")
    #expect(snapshot.scanMode == "allDevices")
    #expect(snapshot.targetPeripheralID == "DEVICE")
    #expect(snapshot.connectionState.contains("connecting"))
    #expect(snapshot.discoveredPeripherals.count == 1)
    #expect(snapshot.lastActivationStatus == 123)
    #expect(snapshot.lastDisconnectStatus == 0)
}

@MainActor
@Test
func debugSnapshotIsCodable() {
    let snapshot = BluetoothMIDIDebugSnapshot(
        centralStateRawValue: 5,
        authorization: "denied",
        isScanning: false,
        scanMode: "midiServiceFiltered",
        coreMIDIDeviceCount: 0,
        coreMIDISourceCount: 0,
        coreMIDIDestinationCount: 0,
        lastError: "x",
        discoveredPeripherals: [],
        targetPeripheralID: nil,
        connectionState: "idle",
        lastActivationStatus: nil,
        lastDisconnectStatus: nil
    )

    let encoder = JSONEncoder()
    #expect((try? encoder.encode(snapshot)) != nil)
}
