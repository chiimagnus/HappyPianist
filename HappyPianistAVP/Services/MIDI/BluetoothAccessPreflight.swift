import CoreBluetooth
import Foundation

@MainActor
protocol BluetoothAccessPreflightProtocol: AnyObject {
    func checkOrRequestAccess() async -> BluetoothAccessPreflight.Status
}

@MainActor
final class BluetoothAccessPreflight: NSObject, BluetoothAccessPreflightProtocol, CBCentralManagerDelegate {
    enum Status: Equatable {
        case ready
        case bluetoothPoweredOff
        case unauthorized
        case unsupported
        case unknown
    }

    private let timeout: Duration
    private let pollInterval: Duration
    private var centralManager: CBCentralManager?

    init(timeout: Duration = .seconds(5), pollInterval: Duration = .milliseconds(100)) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    func checkOrRequestAccess() async -> Status {
        let manager: CBCentralManager
        if let centralManager {
            manager = centralManager
        } else {
            manager = CBCentralManager(delegate: self, queue: nil)
            centralManager = manager
        }
        return await waitForStableState(manager)
    }

    func centralManagerDidUpdateState(_: CBCentralManager) {
        // `waitForStableState` observes the manager after each delegate-driven state update.
    }

    private func waitForStableState(_ central: CBCentralManager) async -> Status {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while true {
            let status = mapStatus(central)
            if status != .unknown {
                return status
            }
            guard clock.now < deadline else { return .unknown }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return .unknown
            }
        }
    }

    private func mapStatus(_ central: CBCentralManager) -> Status {
        switch CBManager.authorization {
        case .allowedAlways:
            break
        case .denied, .restricted:
            return .unauthorized
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }

        switch central.state {
        case .poweredOn:
            return .ready
        case .poweredOff:
            return .bluetoothPoweredOff
        case .unauthorized:
            return .unauthorized
        case .unsupported:
            return .unsupported
        case .unknown, .resetting:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}
