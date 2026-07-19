import AudioToolbox
import AVFAudio
import Foundation
@testable import HappyPianistAVP
import os

final class FakePerformanceOutput: MIDIOutputSendingProtocol, @unchecked Sendable {
    enum Call: Equatable {
        case start
        case stop
        case noteOn(note: UInt8, velocity: UInt8, channel: UInt8, destination: Int32)
        case noteOff(note: UInt8, channel: UInt8, destination: Int32)
        case controlChange(controller: UInt8, value: UInt8, channel: UInt8, destination: Int32)
        case programChange(program: UInt8, channel: UInt8, destination: Int32)
        case bytes([UInt8], destination: Int32)
        case flush(destination: Int32)
    }

    struct TimestampedBatch: Equatable {
        let generation: UInt64?
        let capabilities: PerformanceOutputCapabilities
        let destinationUniqueID: Int32
        let messages: [TimestampedMIDI1Message]
    }

    enum AudioEntry: Equatable {
        case sequenceStopped
        case midi(status: UInt32, data1: UInt32, data2: UInt32)
        case state(PracticeAudioPlaybackState)
    }

    enum AudioOperation: Hashable {
        case audioSessionConfiguration
        case soundBankLoad
        case engineStart
        case sequenceLoad
        case sequenceStart
    }

    private struct State {
        var onDestinationRouteWillChange: (@Sendable () -> Void)?
        var onDestinationRouteChange: (@Sendable () -> Void)?
        var calls: [Call] = []
        var timestampedBatches: [TimestampedBatch] = []
        var failingControllers: Set<UInt8>
        var failingMIDIBatchCount = 0
        var audioEntries: [AudioEntry] = []
        var audioFailures: [AudioOperation: Int] = [:]
        var failingAudioControllers: Set<UInt32> = []
        var failingAudioStatusKinds: Set<UInt32> = []
        var isSoundFontAvailable = true
    }

    let capabilities: PerformanceOutputCapabilities

    private let generation: @Sendable () -> UInt64?
    private let lock: OSAllocatedUnfairLock<State>

    init(
        capabilities: PerformanceOutputCapabilities = .externalMIDI,
        generation: @escaping @Sendable () -> UInt64? = { nil },
        failingControllers: Set<UInt8> = []
    ) {
        self.capabilities = capabilities
        self.generation = generation
        lock = OSAllocatedUnfairLock(initialState: State(failingControllers: failingControllers))
    }

    var onDestinationRouteWillChange: (@Sendable () -> Void)? {
        get { lock.withLock { $0.onDestinationRouteWillChange } }
        set { lock.withLock { $0.onDestinationRouteWillChange = newValue } }
    }

    var onDestinationRouteChange: (@Sendable () -> Void)? {
        get { lock.withLock { $0.onDestinationRouteChange } }
        set { lock.withLock { $0.onDestinationRouteChange = newValue } }
    }

    func callsSnapshot() -> [Call] {
        lock.withLock { $0.calls }
    }

    func timestampedBatchesSnapshot() -> [TimestampedBatch] {
        lock.withLock { $0.timestampedBatches }
    }

    func audioEntriesSnapshot() -> [AudioEntry] {
        lock.withLock { $0.audioEntries }
    }

    func removeAllAudioEntries() {
        lock.withLock { $0.audioEntries.removeAll(keepingCapacity: true) }
    }

    func failNextMIDIBatch() {
        lock.withLock { $0.failingMIDIBatchCount += 1 }
    }

    func failNextAudioOperation(_ operation: AudioOperation) {
        lock.withLock { $0.audioFailures[operation, default: 0] += 1 }
    }

    func setFailingAudioControllers(_ controllers: Set<UInt32>) {
        lock.withLock { $0.failingAudioControllers = controllers }
    }

    func setFailingAudioStatusKinds(_ statusKinds: Set<UInt32>) {
        lock.withLock { $0.failingAudioStatusKinds = statusKinds }
    }

    func setSoundFontAvailable(_ isAvailable: Bool) {
        lock.withLock { $0.isSoundFontAvailable = isAvailable }
    }

    func record(state: PracticeAudioPlaybackState) {
        lock.withLock { $0.audioEntries.append(.state(state)) }
    }

    func resetControllersBeforeLastAudioState() -> [UInt32] {
        let entries = audioEntriesSnapshot()
        guard let stateIndex = entries.lastIndex(where: {
            if case .state = $0 { return true }
            return false
        }) else { return [] }
        return entries[..<stateIndex].compactMap { entry in
            guard case let .midi(_, data1, _) = entry else { return nil }
            return data1
        }
    }

    func makeAudioPlatform() -> PracticeAudioPlatformOperations {
        PracticeAudioPlatformOperations(
            resolveSoundFontURL: { [weak self] _ in
                guard let self, lock.withLock({ $0.isSoundFontAvailable }) else { return nil }
                return URL(fileURLWithPath: "/tmp/TestSoundFont.sf2")
            },
            configureAudioSession: { [weak self] in
                try self?.consumeAudioFailure(.audioSessionConfiguration)
            },
            loadSoundBank: { [weak self] _, _, _ in
                try self?.consumeAudioFailure(.soundBankLoad)
            },
            startEngine: { [weak self] _ in
                try self?.consumeAudioFailure(.engineStart)
            },
            loadSequence: { [weak self] _, _ in
                try self?.consumeAudioFailure(.sequenceLoad)
            },
            startSequence: { [weak self] _ in
                try self?.consumeAudioFailure(.sequenceStart)
            },
            stopSequence: { [weak self] _ in
                self?.lock.withLock { $0.audioEntries.append(.sequenceStopped) }
            },
            sendMIDIEvent: { [weak self] _, status, data1, data2 in
                self?.recordAudioMIDI(status: status, data1: data1, data2: data2) ?? -1
            }
        )
    }

    func start() throws {
        lock.withLock { $0.calls.append(.start) }
    }

    func stop() {
        lock.withLock { $0.calls.append(.stop) }
    }

    func listDestinations() -> [MIDIDestinationInfo] {
        []
    }

    func sendMIDI1Messages(
        _ messages: [TimestampedMIDI1Message],
        destinationUniqueID: Int32
    ) throws {
        let generation = generation()
        let shouldFail = lock.withLock { state in
            state.timestampedBatches.append(TimestampedBatch(
                generation: generation,
                capabilities: capabilities,
                destinationUniqueID: destinationUniqueID,
                messages: messages
            ))
            state.calls.append(contentsOf: messages.map { .bytes($0.bytes, destination: destinationUniqueID) })
            guard state.failingMIDIBatchCount > 0 else { return false }
            state.failingMIDIBatchCount -= 1
            return true
        }
        if shouldFail { throw FakePerformanceOutputFailure.injected }
    }

    func flushScheduledMessages(destinationUniqueID: Int32) throws {
        lock.withLock { $0.calls.append(.flush(destination: destinationUniqueID)) }
    }

    func simulateDestinationDisconnect() {
        let callbacks = lock.withLock {
            ($0.onDestinationRouteWillChange, $0.onDestinationRouteChange)
        }
        callbacks.0?()
        callbacks.1?()
    }

    func sendNoteOn(
        note: UInt8,
        velocity: UInt8,
        channel: UInt8,
        destinationUniqueID: Int32
    ) throws {
        lock.withLock {
            $0.calls.append(.noteOn(
                note: note,
                velocity: velocity,
                channel: channel,
                destination: destinationUniqueID
            ))
        }
    }

    func sendNoteOff(note: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock {
            $0.calls.append(.noteOff(note: note, channel: channel, destination: destinationUniqueID))
        }
    }

    func sendControlChange(
        controller: UInt8,
        value: UInt8,
        channel: UInt8,
        destinationUniqueID: Int32
    ) throws {
        let shouldFail = lock.withLock { state in
            state.calls.append(.controlChange(
                controller: controller,
                value: value,
                channel: channel,
                destination: destinationUniqueID
            ))
            return state.failingControllers.contains(controller)
        }
        if shouldFail { throw FakePerformanceOutputFailure.injected }
    }

    func sendProgramChange(program: UInt8, channel: UInt8, destinationUniqueID: Int32) throws {
        lock.withLock {
            $0.calls.append(.programChange(
                program: program,
                channel: channel,
                destination: destinationUniqueID
            ))
        }
    }

    func sendAllNotesOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(
            controller: 123,
            value: 0,
            channel: channel,
            destinationUniqueID: destinationUniqueID
        )
    }

    func sendAllSoundOff(channel: UInt8, destinationUniqueID: Int32) throws {
        try sendControlChange(
            controller: 120,
            value: 0,
            channel: channel,
            destinationUniqueID: destinationUniqueID
        )
    }

    private func consumeAudioFailure(_ operation: AudioOperation) throws {
        let shouldFail = lock.withLock { state in
            guard let remaining = state.audioFailures[operation], remaining > 0 else { return false }
            state.audioFailures[operation] = remaining - 1
            return true
        }
        if shouldFail { throw FakePerformanceOutputFailure.injected }
    }

    private func recordAudioMIDI(status: UInt32, data1: UInt32, data2: UInt32) -> OSStatus {
        lock.withLock { state in
            state.audioEntries.append(.midi(status: status, data1: data1, data2: data2))
            let statusKind = status & 0xF0
            if state.failingAudioControllers.contains(data1) ||
                state.failingAudioStatusKinds.contains(statusKind)
            {
                return -1
            }
            return noErr
        }
    }
}

private enum FakePerformanceOutputFailure: Error {
    case injected
}
