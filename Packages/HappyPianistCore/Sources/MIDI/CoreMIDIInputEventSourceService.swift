import CoreMIDI
import Darwin
import Diagnostics
import Foundation
import os

public enum CoreMIDIInputEventSourceServiceError: LocalizedError {
    case clientCreate(OSStatus)
    case portCreate(OSStatus)
    case sourceRefresh(OSStatus)

    public var errorDescription: String? {
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

public final class CoreMIDIInputEventSourceService: MIDIInputEventSource, Sendable {
    private static let streamBufferCapacity = 2048
    private static let allNotesOffController = 123
    private static let hostTimeToSecondsScale: Double? = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return nil }
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    public func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        midi1EventsBroadcaster.makeStream(bufferingPolicy: .bufferingNewest(Self.streamBufferCapacity))
    }

    public func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        midi2EventsBroadcaster.makeStream(bufferingPolicy: .bufferingNewest(Self.streamBufferCapacity))
    }

    public var onSourceAvailabilityChange: (@Sendable (MIDIInputSourceAvailability) -> Void)? {
        get { stateLock.withLock { $0.onSourceAvailabilityChange } }
        set { stateLock.withLock { $0.onSourceAvailabilityChange = newValue } }
    }

    private let selection: MIDIInputSourceSelection
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let refreshScheduler = MIDIRefreshDebouncer(debounce: .milliseconds(200))
    private let lifecycleLock = OSAllocatedUnfairLock(initialState: CoreMIDILifecycleState())
    private let stateLock = OSAllocatedUnfairLock(initialState: CoreMIDIInputEventSourceState())

    private let midi1EventsBroadcaster = MIDIAsyncStreamBroadcaster<MIDI1InputEvent>()
    private let midi2EventsBroadcaster = MIDIAsyncStreamBroadcaster<MIDI2InputEvent>()

    private let midi1Decoder = MIDI1MessageDecoder()
    private let midi2Decoder = MIDI2MessageDecoder()

    public init(
        selection: MIDIInputSourceSelection = .allCurrentSources,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.selection = selection
        self.diagnosticsReporter = diagnosticsReporter
    }

    public func start() throws {
        let shouldStart = stateLock.withLock { state in
            if state.isRunning { return false }
            state.isRunning = true
            state.lastProtocolMismatchLoggedAtUptimeSeconds = 0
            state.lastOverflowRecoveryUptimeSecondsByProtocol.removeAll(keepingCapacity: true)
            state.droppedEventCount = 0
            return true
        }
        guard shouldStart else { return }

        do {
            try lifecycleLock.withLock { lifecycle in
                guard stateLock.withLock({ $0.isRunning }) else { return }
                try createClientIfNeeded(state: &lifecycle)
                try createMIDI1InputPortIfNeeded(state: &lifecycle)
                try createMIDI2InputPortIfNeeded(state: &lifecycle)
                try refreshSourcesLocked(state: &lifecycle)
            }
        } catch {
            stateLock.withLock { $0.isRunning = false }
            lifecycleLock.withLock { stopLifecycleLocked(state: &$0) }
            throw error
        }
    }

    public func stop() {
        stateLock.withLock { $0.isRunning = false }
        refreshScheduler.cancel()
        lifecycleLock.withLock { stopLifecycleLocked(state: &$0) }
    }

    public func refreshSources() throws {
        try lifecycleLock.withLock { lifecycle in
            guard stateLock.withLock({ $0.isRunning }) else { return }
            try refreshSourcesLocked(state: &lifecycle)
        }
    }

    public func availableSources() -> [MIDIInputEndpoint] {
        Self.availableSources()
    }

    private func refreshSourcesLocked(state: inout CoreMIDILifecycleState) throws {
        guard state.midi1InputPortRef != 0 || state.midi2InputPortRef != 0 else { return }

        disconnectAllSources(state: &state)

        var failedStatus: OSStatus?
        var selectedEndpointWasPresent = false

        for source in Self.sourceEndpoints() {
            guard selection.accepts(endpointUniqueID: source.info.id) else { continue }
            selectedEndpointWasPresent = true

            let connectionContext = EndpointConnectionContext(
                endpointUniqueID: source.info.id,
                endpointName: source.info.name
            )
            let connRefCon = Unmanaged.passUnretained(connectionContext).toOpaque()

            let endpointProtocolID = MIDIEndpointPropertyReader.int32Property(source.endpoint, kMIDIPropertyProtocolID)
                .flatMap(MIDIProtocolID.init(rawValue:))
            if endpointProtocolID == ._2_0, state.midi2InputPortRef == 0 {
                diagnosticsReporter?.recordSystem(
                    severity: .warning,
                    category: .midi,
                    stage: "coreMIDI.inputSubscribe",
                    summary: "MIDI 2.0 端点改用 MIDI 1.0 端口",
                    reason: "midi2PortUnavailable"
                )
            }
            let targetProtocol = MIDIEndpointConnectionPolicy.subscribedProtocol(
                endpointProtocolID: endpointProtocolID,
                midi2PortAvailable: state.midi2InputPortRef != 0
            )
            let targetPortRef = targetProtocol == ._2_0 ? state.midi2InputPortRef : state.midi1InputPortRef

            let status = MIDIPortConnectSource(targetPortRef, source.endpoint, connRefCon)
            if status == noErr {
                state.connectedSources.append(ConnectedSource(
                    portRef: targetPortRef,
                    endpoint: source.endpoint,
                    connectionContext: connectionContext
                ))
            } else {
                failedStatus = status
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .midi,
                    stage: "coreMIDI.connectSource",
                    summary: "连接 MIDI 输入源失败",
                    reason: "status=\(status)"
                )
            }
        }

        let availability: MIDIInputSourceAvailability = switch selection {
        case .allCurrentSources:
            .connected(selection: selection, sourceCount: state.connectedSources.count)
        case let .endpointUniqueID(endpointID):
            selectedEndpointWasPresent
                ? .connected(selection: selection, sourceCount: state.connectedSources.count)
                : .selectedEndpointUnavailable(endpointID)
        }
        let callback = stateLock.withLock { $0.onSourceAvailabilityChange }
        callback?(availability)

        if state.connectedSources.isEmpty, let failedStatus {
            throw CoreMIDIInputEventSourceServiceError.sourceRefresh(failedStatus)
        }
    }

    private func createClientIfNeeded(state: inout CoreMIDILifecycleState) throws {
        guard state.clientRef == 0 else { return }

        let status = MIDIClientCreateWithBlock(
            "HappyPianistAVPCoreMIDIEventsClient" as CFString,
            &state.clientRef
        ) { [weak self] message in
            self?.handleMIDINotification(message)
        }

        guard status == noErr else {
            throw CoreMIDIInputEventSourceServiceError.clientCreate(status)
        }
    }

    private func createMIDI1InputPortIfNeeded(state: inout CoreMIDILifecycleState) throws {
        guard state.midi1InputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            state.clientRef,
            "HappyPianistAVPCoreMIDIEventsInput-MIDI1" as CFString,
            MIDIProtocolID._1_0,
            &state.midi1InputPortRef
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            self.handleEventList(eventList, srcConnRefCon: srcConnRefCon)
        }

        guard status == noErr else {
            throw CoreMIDIInputEventSourceServiceError.portCreate(status)
        }
    }

    private func createMIDI2InputPortIfNeeded(state: inout CoreMIDILifecycleState) throws {
        guard state.midi2InputPortRef == 0 else { return }

        let status = MIDIInputPortCreateWithProtocol(
            state.clientRef,
            "HappyPianistAVPCoreMIDIEventsInput-MIDI2" as CFString,
            MIDIProtocolID._2_0,
            &state.midi2InputPortRef
        ) { [weak self] eventList, srcConnRefCon in
            guard let self else { return }
            self.handleEventList(eventList, srcConnRefCon: srcConnRefCon)
        }

        if status != noErr {
            diagnosticsReporter?.recordSystem(
                severity: .warning,
                category: .midi,
                stage: "coreMIDI.createMIDI2Port",
                summary: "MIDI 2.0 端口创建失败，将只使用 MIDI 1.0",
                reason: "status=\(status)"
            )
            state.midi2InputPortRef = 0
        }
    }

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        guard MIDIEndpointRouteNotificationPolicy.affectsSources(notification) else {
            return
        }
        scheduleRefreshSources()
    }

    private func scheduleRefreshSources() {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        refreshScheduler.schedule { [weak self] in
            guard let self, self.stateLock.withLock({ $0.isRunning }) else { return }
            do {
                try self.refreshSources()
            } catch {
                self.diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .midi,
                    stage: "coreMIDI.refreshSources",
                    summary: "自动刷新 MIDI 输入源失败",
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func stopLifecycleLocked(state: inout CoreMIDILifecycleState) {
        disconnectAllSources(state: &state)

        if state.midi1InputPortRef != 0 {
            MIDIPortDispose(state.midi1InputPortRef)
            state.midi1InputPortRef = 0
        }
        if state.midi2InputPortRef != 0 {
            MIDIPortDispose(state.midi2InputPortRef)
            state.midi2InputPortRef = 0
        }
        if state.clientRef != 0 {
            MIDIClientDispose(state.clientRef)
            state.clientRef = 0
        }
    }

    private func disconnectAllSources(state: inout CoreMIDILifecycleState) {
        for source in state.connectedSources {
            MIDIPortDisconnectSource(source.portRef, source.endpoint)
        }
        state.connectedSources.removeAll(keepingCapacity: false)
    }

    private func handleEventList(_ eventList: UnsafePointer<MIDIEventList>, srcConnRefCon: UnsafeMutableRawPointer?) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        let protocolID = eventList.pointee.protocol
        var context = MIDIEventListVisitorContext(
            service: self,
            protocolID: protocolID,
            srcConnRefCon: srcConnRefCon
        )
        withUnsafeMutablePointer(to: &context) { pointer in
            MIDIEventListForEachEvent(eventList, midiEventVisitor, UnsafeMutableRawPointer(pointer))
        }
    }

    fileprivate func handleUniversalMessage(
        _ message: MIDIUniversalMessage,
        timeStamp: MIDITimeStamp,
        protocolID: MIDIProtocolID,
        srcConnRefCon: UnsafeMutableRawPointer?
    ) {
        guard stateLock.withLock({ $0.isRunning }) else { return }
        let receivedAt = Date.now
        let receivedAtUptimeSeconds = ProcessInfo.processInfo.systemUptime
        let sourceTimestamp = Self.hostTimeToSecondsScale.flatMap { scale in
            timeStamp == 0 ? nil : PerformanceSourceTimestamp(
                clockID: "coremidi-host-time",
                seconds: Double(timeStamp) * scale
            )
        }
        let source = sourceIdentity(from: srcConnRefCon)
        let group = Int(message.group)

        switch message.type {
        case .channelVoice1:
            if protocolID != ._1_0 {
                logProtocolMismatchIfNeeded(
                    uptimeSeconds: receivedAtUptimeSeconds,
                    expected: ._1_0,
                    actual: protocolID,
                    messageType: "channelVoice1"
                )
            }

            let voice = message.channelVoice1
            let channel = Int(voice.channel) + 1
            guard let kind = midi1Decoder.decode(message) else { return }
            let event = MIDI1InputEvent(
                kind: kind,
                channel: channel,
                group: group,
                source: source,
                receivedAt: receivedAt,
                receivedAtUptimeSeconds: receivedAtUptimeSeconds,
                sourceTimestamp: sourceTimestamp
            )
            if midi1EventsBroadcaster.yield(event) > 0 {
                recoverMIDI1StreamAfterOverflow(
                    channel: channel,
                    group: group,
                    source: source,
                    receivedAt: receivedAt,
                    uptimeSeconds: receivedAtUptimeSeconds
                )
            }

        case .channelVoice2:
            if protocolID != ._2_0 {
                logProtocolMismatchIfNeeded(
                    uptimeSeconds: receivedAtUptimeSeconds,
                    expected: ._2_0,
                    actual: protocolID,
                    messageType: "channelVoice2"
                )
            }

            let voice = message.channelVoice2
            let channel = Int(voice.channel) + 1
            guard let kind = midi2Decoder.decode(message) else { return }

            let event = MIDI2InputEvent(
                kind: kind,
                channel: channel,
                group: group,
                source: source,
                receivedAt: receivedAt,
                receivedAtUptimeSeconds: receivedAtUptimeSeconds,
                sourceTimestamp: sourceTimestamp
            )
            if midi2EventsBroadcaster.yield(event) > 0 {
                recoverMIDI2StreamAfterOverflow(
                    channel: channel,
                    group: group,
                    source: source,
                    receivedAt: receivedAt,
                    uptimeSeconds: receivedAtUptimeSeconds
                )
            }

        default:
            return
        }
    }

    private func recoverMIDI1StreamAfterOverflow(
        channel: Int,
        group: Int,
        source: MIDIInputSource,
        receivedAt: Date,
        uptimeSeconds: TimeInterval
    ) {
        guard shouldPublishOverflowRecovery(for: .midi1, uptimeSeconds: uptimeSeconds) else { return }
        // ponytail: the app intentionally collapses MIDI channels into one practice state, so one
        // protocol-native marker resets every downstream note cache without causing 16 duplicate resets.
        midi1EventsBroadcaster.yield(MIDI1InputEvent(
            kind: .controlChange(controller: Self.allNotesOffController, value: 0),
            channel: channel,
            group: group,
            source: source,
            receivedAt: receivedAt,
            receivedAtUptimeSeconds: uptimeSeconds
        ))
    }

    private func recoverMIDI2StreamAfterOverflow(
        channel: Int,
        group: Int,
        source: MIDIInputSource,
        receivedAt: Date,
        uptimeSeconds: TimeInterval
    ) {
        guard shouldPublishOverflowRecovery(for: .midi2, uptimeSeconds: uptimeSeconds) else { return }
        midi2EventsBroadcaster.yield(MIDI2InputEvent(
            kind: .controlChange(controller: Self.allNotesOffController, value32: 0),
            channel: channel,
            group: group,
            source: source,
            receivedAt: receivedAt,
            receivedAtUptimeSeconds: uptimeSeconds
        ))
    }

    private func shouldPublishOverflowRecovery(
        for inputProtocol: CoreMIDIInputProtocol,
        uptimeSeconds: TimeInterval
    ) -> Bool {
        let shouldRecover = stateLock.withLock { state in
            state.droppedEventCount += 1
            let lastRecovery = state.lastOverflowRecoveryUptimeSecondsByProtocol[inputProtocol] ?? -.infinity
            guard uptimeSeconds - lastRecovery >= 0.25 else { return false }
            state.lastOverflowRecoveryUptimeSecondsByProtocol[inputProtocol] = uptimeSeconds
            return true
        }
        guard shouldRecover else { return false }
        diagnosticsReporter?.recordSystem(
            severity: .error,
            category: .midi,
            stage: "coreMIDI.streamOverflow",
            summary: "MIDI 输入流溢出，已发送全通道复位",
            reason: "protocol=\(inputProtocol.logName)"
        )
        return true
    }

    private func sourceIdentity(from srcConnRefCon: UnsafeMutableRawPointer?) -> MIDIInputSource {
        guard let srcConnRefCon else {
            return MIDIInputSource(identifier: .unidentified, endpointName: nil)
        }

        let context = Unmanaged<EndpointConnectionContext>
            .fromOpaque(srcConnRefCon)
            .takeUnretainedValue()
        return MIDIInputSource(
            identifier: .endpointUniqueID(context.endpointUniqueID),
            endpointName: context.endpointName
        )
    }

    private static func sourceEndpoints() -> [(endpoint: MIDIEndpointRef, info: MIDIInputEndpoint)] {
        let sourceCount = MIDIGetNumberOfSources()
        var sources: [(endpoint: MIDIEndpointRef, info: MIDIInputEndpoint)] = []
        sources.reserveCapacity(max(0, sourceCount))

        for index in 0 ..< sourceCount {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0,
                  let uniqueID = MIDIEndpointPropertyReader.int32Property(endpoint, kMIDIPropertyUniqueID)
            else { continue }
            let name = MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyDisplayName) ??
                MIDIEndpointPropertyReader.stringProperty(endpoint, kMIDIPropertyName) ??
                "Unknown MIDI Source"
            sources.append((endpoint, MIDIInputEndpoint(id: uniqueID, name: name)))
        }
        return sources
    }

    private static func availableSources() -> [MIDIInputEndpoint] {
        sourceEndpoints()
            .map(\.info)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func logProtocolMismatchIfNeeded(
        uptimeSeconds: TimeInterval,
        expected: MIDIProtocolID,
        actual: MIDIProtocolID,
        messageType: String
    ) {
        let shouldLog = stateLock.withLock { state in
            if uptimeSeconds - state.lastProtocolMismatchLoggedAtUptimeSeconds < 2 {
                return false
            }
            state.lastProtocolMismatchLoggedAtUptimeSeconds = uptimeSeconds
            return true
        }
        guard shouldLog else { return }

        diagnosticsReporter?.recordSystem(
            severity: .warning,
            category: .midi,
            stage: "coreMIDI.protocolMismatch",
            summary: "检测到 MIDI 协议不匹配",
            reason: "messageType=\(messageType), expected=\(expected.rawValue), actual=\(actual.rawValue)"
        )
    }
}

private enum CoreMIDIInputProtocol: Hashable {
    case midi1
    case midi2

    var logName: String {
        switch self {
        case .midi1: "MIDI 1"
        case .midi2: "MIDI 2"
        }
    }
}

private struct CoreMIDILifecycleState {
    var clientRef: MIDIClientRef = 0
    var midi1InputPortRef: MIDIPortRef = 0
    var midi2InputPortRef: MIDIPortRef = 0
    var connectedSources: [ConnectedSource] = []
}

private struct CoreMIDIInputEventSourceState {
    var isRunning = false
    var onSourceAvailabilityChange: (@Sendable (MIDIInputSourceAvailability) -> Void)?
    var lastProtocolMismatchLoggedAtUptimeSeconds: TimeInterval = 0
    var lastOverflowRecoveryUptimeSecondsByProtocol: [CoreMIDIInputProtocol: TimeInterval] = [:]
    var droppedEventCount = 0
}

private final class EndpointConnectionContext: Sendable {
    let endpointUniqueID: Int32
    let endpointName: String

    init(endpointUniqueID: Int32, endpointName: String) {
        self.endpointUniqueID = endpointUniqueID
        self.endpointName = endpointName
    }
}

private struct ConnectedSource {
    let portRef: MIDIPortRef
    let endpoint: MIDIEndpointRef
    let connectionContext: EndpointConnectionContext
}

private struct MIDIEventListVisitorContext {
    let service: CoreMIDIInputEventSourceService
    let protocolID: MIDIProtocolID
    let srcConnRefCon: UnsafeMutableRawPointer?
}

private func midiEventVisitor(
    context: UnsafeMutableRawPointer?,
    timeStamp: MIDITimeStamp,
    message: MIDIUniversalMessage
) {
    guard let context else { return }
    let typed = context.assumingMemoryBound(to: MIDIEventListVisitorContext.self).pointee
    typed.service.handleUniversalMessage(
        message,
        timeStamp: timeStamp,
        protocolID: typed.protocolID,
        srcConnRefCon: typed.srcConnRefCon
    )
}
