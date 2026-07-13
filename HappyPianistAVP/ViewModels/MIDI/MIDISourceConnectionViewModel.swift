import Foundation
import Observation

@MainActor
@Observable
final class MIDISourceConnectionViewModel {
    private let monitoringService: MIDISourceMonitoringServiceProtocol

    var sourceNames: [String] = []
    var connectionState: MIDISourceMonitoringConnectionState = .idle
    var lastErrorMessage: String?

    init(monitoringService: MIDISourceMonitoringServiceProtocol? = nil) {
        let monitoringService = monitoringService ?? CoreMIDISourceMonitoringService()
        self.monitoringService = monitoringService

        monitoringService.onSourceNamesChange = { [weak self] names in
            self?.sourceNames = names
        }
        monitoringService.onConnectionStateChange = { [weak self] state in
            self?.connectionState = state
        }
        monitoringService.onLastErrorMessageChange = { [weak self] message in
            self?.lastErrorMessage = message
        }
    }

    var sourceCount: Int {
        switch connectionState {
        case let .connected(sourceCount):
            sourceCount
        case .idle, .failed:
            0
        }
    }

    var statusText: String {
        switch connectionState {
        case .idle:
            "idle"
        case let .connected(sourceCount):
            "connected: \(sourceCount)"
        case let .failed(message):
            "failed: \(message)"
        }
    }

    func start() {
        do {
            try monitoringService.start()
        } catch {
            connectionState = .failed(message: error.localizedDescription)
        }
    }

    func stop() {
        monitoringService.stop()
    }

    func refreshSources() {
        do {
            try monitoringService.refreshSources()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
