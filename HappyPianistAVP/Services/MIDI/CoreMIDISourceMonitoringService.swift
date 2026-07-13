import CoreMIDI
import Foundation
import OSLog

enum CoreMIDISourceMonitoringServiceError: LocalizedError {
    case clientCreate(OSStatus)
    case portCreate(OSStatus)
    case sourceRefresh(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .clientCreate(status):
            "Failed to create MIDI client: \(status)"
        case let .portCreate(status):
            "Failed to create MIDI input port: \(status)"
        case let .sourceRefresh(status):
            "Failed to refresh MIDI sources: \(status)"
        }
    }
}

@MainActor
final class CoreMIDISourceMonitoringService: MIDISourceMonitoringServiceProtocol {
    var onConnectionStateChange: ((MIDISourceMonitoringConnectionState) -> Void)?
    var onSourceNamesChange: (([String]) -> Void)?
    var onLastErrorMessageChange: ((String?) -> Void)?

    private let logger = Logger(subsystem: "com.chiimagnus.HappyPianist", category: "CoreMIDI-AVP-Sources")
    private let refreshScheduler = DebouncedActionScheduler(debounce: .milliseconds(200))

    private var clientRef: MIDIClientRef = 0
    private var midi1InputPortRef: MIDIPortRef = 0
    private var midi2InputPortRef: MIDIPortRef = 0
    private var connectedSources: [ConnectedSource] = []
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        do {
            try createClientIfNeeded()
            try createInputPortsIfNeeded()
            isRunning = true
            try refreshSources()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        isRunning = false
        refreshScheduler.cancel()

        disconnectAllSources()

        if midi1InputPortRef != 0 {
            MIDIPortDispose(midi1InputPortRef)
            midi1InputPortRef = 0
        }

        if midi2InputPortRef != 0 {
            MIDIPortDispose(midi2InputPortRef)
            midi2InputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }

        onLastErrorMessageChange?(nil)
        onConnectionStateChange?(.idle)
    }

    func refreshSources() throws {
        guard midi1InputPortRef != 0 || midi2InputPortRef != 0 else {
            onLastErrorMessageChange?("MIDI input port is unavailable")
            onSourceNamesChange?([])
            onConnectionStateChange?(.connected(sourceCount: 0))
            return
        }

        disconnectAllSources()

        var failedStatus: OSStatus?
        let sourceCount = MIDIGetNumberOfSources()

        for index in 0 ..< sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }

            let endpointProtocolID = MIDIEndpointPropertyReader.int32Property(source, kMIDIPropertyProtocolID)
                .flatMap(MIDIProtocolID.init(rawValue:))
            let targetProtocol = MIDIEndpointConnectionPolicy.subscribedProtocol(
                endpointProtocolID: endpointProtocolID,
                midi2PortAvailable: midi2InputPortRef != 0
            )
            let targetPortRef = targetProtocol == ._2_0 ? midi2InputPortRef : midi1InputPortRef

            let status = MIDIPortConnectSource(targetPortRef, source, nil)
            if status == noErr {
                connectedSources.append(ConnectedSource(portRef: targetPortRef, endpoint: source))
            } else {
                failedStatus = status
                logger.error("Failed to connect source \(index, privacy: .public): \(status, privacy: .public)")
            }
        }

        let names = connectedSources.map { endpointName($0.endpoint) }
        onSourceNamesChange?(names)
        onConnectionStateChange?(.connected(sourceCount: connectedSources.count))

        if connectedSources.isEmpty, let failedStatus {
            onLastErrorMessageChange?("Connect sources failed: \(failedStatus)")
        } else {
            onLastErrorMessageChange?(nil)
        }
    }

    private func createClientIfNeeded() throws {
        guard clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "HappyPianistAVPSourcesClient" as CFString,
            &clientRef
        ) { [weak self] message in
            let notification = message.pointee
            Task { @MainActor [weak self] in
                self?.handleMIDINotification(notification)
            }
        }

        guard status == noErr else {
            throw CoreMIDISourceMonitoringServiceError.clientCreate(status)
        }
    }

    private func createInputPortsIfNeeded() throws {
        if midi1InputPortRef == 0 {
            let status = MIDIInputPortCreateWithProtocol(
                clientRef,
                "HappyPianistAVPSourcesInput-MIDI1" as CFString,
                MIDIProtocolID._1_0,
                &midi1InputPortRef
            ) { _, _ in
                // Source monitoring does not need to parse events.
            }

            guard status == noErr else {
                throw CoreMIDISourceMonitoringServiceError.portCreate(status)
            }
        }

        guard midi2InputPortRef == 0 else { return }
        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "HappyPianistAVPSourcesInput-MIDI2" as CFString,
            MIDIProtocolID._2_0,
            &midi2InputPortRef
        ) { _, _ in
            // Source monitoring does not need to parse events.
        }

        if status != noErr {
            midi2InputPortRef = 0
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        _ = notification
        scheduleRefreshSources()
    }

    private func scheduleRefreshSources() {
        guard isRunning else { return }
        refreshScheduler.schedule { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                do {
                    try self.refreshSources()
                } catch {
                    self.logger.error("Auto refresh MIDI sources failed: \(error.localizedDescription, privacy: .public)")
                    self.onLastErrorMessageChange?(error.localizedDescription)
                    self.onConnectionStateChange?(.connected(sourceCount: self.connectedSources.count))
                }
            }
        }
    }

    private func disconnectAllSources() {
        guard midi1InputPortRef != 0 || midi2InputPortRef != 0 else {
            connectedSources.removeAll(keepingCapacity: false)
            onSourceNamesChange?([])
            return
        }

        for source in connectedSources {
            MIDIPortDisconnectSource(source.portRef, source.endpoint)
        }
        connectedSources.removeAll(keepingCapacity: false)
        onSourceNamesChange?([])
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        if let displayName = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyDisplayName) {
            return displayName
        }
        if let name = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyName) {
            return name
        }
        return "Unknown MIDI Source"
    }
}

private struct ConnectedSource {
    let portRef: MIDIPortRef
    let endpoint: MIDIEndpointRef
}
