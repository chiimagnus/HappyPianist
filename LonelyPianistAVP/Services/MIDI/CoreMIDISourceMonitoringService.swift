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

final class CoreMIDISourceMonitoringService: MIDISourceMonitoringServiceProtocol {
    var onConnectionStateChange: (@Sendable (MIDISourceMonitoringConnectionState) -> Void)?
    var onSourceNamesChange: (@Sendable ([String]) -> Void)?
    var onLastErrorMessageChange: (@Sendable (String?) -> Void)?

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "CoreMIDI-AVP-Sources")
    private let refreshScheduler = DebouncedActionScheduler(queue: .main, debounceSec: 0.2)

    private var clientRef: MIDIClientRef = 0
    private var inputPortRef: MIDIPortRef = 0
    private var connectedSources: [MIDIEndpointRef] = []
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        try createClientIfNeeded()
        try createInputPortIfNeeded()
        isRunning = true
        try refreshSources()
    }

    func stop() {
        isRunning = false
        refreshScheduler.cancel()

        disconnectAllSources()

        if inputPortRef != 0 {
            MIDIPortDispose(inputPortRef)
            inputPortRef = 0
        }

        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }

        onLastErrorMessageChange?(nil)
        onConnectionStateChange?(.idle)
    }

    func refreshSources() throws {
        guard inputPortRef != 0 else {
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

            let status = MIDIPortConnectSource(inputPortRef, source, nil)
            if status == noErr {
                connectedSources.append(source)
            } else {
                failedStatus = status
                logger.error("Failed to connect source \(index, privacy: .public): \(status, privacy: .public)")
            }
        }

        let names = connectedSources.map(endpointName)
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
            "LonelyPianistAVPSourcesClient" as CFString,
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

    private func createInputPortIfNeeded() throws {
        guard inputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            clientRef,
            "LonelyPianistAVPSourcesInput" as CFString,
            MIDIProtocolID._1_0,
            &inputPortRef
        ) { _, _ in
            // Source monitoring does not need to parse events.
        }

        guard status == noErr else {
            throw CoreMIDISourceMonitoringServiceError.portCreate(status)
        }
    }

    private func handleMIDINotification(_ notification: MIDINotification) {
        _ = notification
        scheduleRefreshSources()
    }

    private func scheduleRefreshSources() {
        guard isRunning else { return }
        refreshScheduler.schedule { [weak self] in
            guard let self else { return }
            guard self.isRunning, self.inputPortRef != 0 else { return }

            do {
                try self.refreshSources()
            } catch {
                self.logger.error("Auto refresh MIDI sources failed: \(error.localizedDescription, privacy: .public)")
                self.onLastErrorMessageChange?(error.localizedDescription)
                self.onConnectionStateChange?(.connected(sourceCount: self.connectedSources.count))
            }
        }
    }

    private func disconnectAllSources() {
        guard inputPortRef != 0 else {
            connectedSources.removeAll(keepingCapacity: false)
            onSourceNamesChange?([])
            return
        }

        for source in connectedSources {
            MIDIPortDisconnectSource(inputPortRef, source)
        }
        connectedSources.removeAll(keepingCapacity: false)
        onSourceNamesChange?([])
    }

    private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
        var displayName: Unmanaged<CFString>?
        let displayStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &displayName)
        if displayStatus == noErr, let displayName {
            return displayName.takeUnretainedValue() as String
        }

        var name: Unmanaged<CFString>?
        let nameStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        if nameStatus == noErr, let name {
            return name.takeUnretainedValue() as String
        }

        return "Unknown MIDI Source"
    }
}
