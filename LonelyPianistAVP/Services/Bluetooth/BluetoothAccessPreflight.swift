import CoreBluetooth
import Foundation

@MainActor
final class BluetoothAccessPreflight: NSObject, CBCentralManagerDelegate {
    enum Status: Equatable {
        case ready
        case bluetoothPoweredOff
        case unauthorized
        case unsupported
        case unknown
    }

    private var centralManager: CBCentralManager?
    private var pendingContinuation: CheckedContinuation<Status, Never>?

    func checkOrRequestAccess() async -> Status {
        if let centralManager {
            return await waitForStableState(centralManager)
        }

        let manager = CBCentralManager(delegate: self, queue: nil)
        centralManager = manager
        return await waitForStableState(manager)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        pendingContinuation?.resume(returning: mapStatus(central))
        pendingContinuation = nil
    }

    private func waitForStableState(_ central: CBCentralManager) async -> Status {
        let immediate = mapStatus(central)
        switch immediate {
            case .ready, .bluetoothPoweredOff, .unauthorized, .unsupported:
                return immediate
            case .unknown:
                break
        }

        return await withCheckedContinuation { continuation in
            pendingContinuation?.resume(returning: .unknown)
            pendingContinuation = continuation
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
            case .unsupported:
                return .unsupported
            case .unknown, .resetting:
                return .unknown
            @unknown default:
                return .unknown
        }
    }
}

