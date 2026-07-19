import AudioToolbox
import AVFAudio
import Foundation
@testable import HappyPianistAVP
import os
import Testing

@Test
func sequencerPlaybackServiceProtocolCarriesCanonicalCommandsAcrossActorBoundary() async throws {
    actor FakeSequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol {
        private(set) var resetCommands: [PerformanceTransportCommand] = []
        private(set) var commands: [PracticePlaybackCommand] = []

        func warmUp() async throws {}
        func stop(resetCommands: [PerformanceTransportCommand]) async {
            self.resetCommands = resetCommands
        }
        func load(sequence _: PracticeSequencerSequence) async throws {}
        func play(fromSeconds _: TimeInterval) async throws {}
        func currentSeconds() async -> TimeInterval {
            0
        }

        func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) async throws {}
        func execute(commands: [PracticePlaybackCommand]) async throws {
            self.commands.append(contentsOf: commands)
        }
        func stopAllLiveNotes() async {}

        func snapshot() -> (commands: [PracticePlaybackCommand], reset: [PerformanceTransportCommand]) {
            (commands, resetCommands)
        }
    }

    func accept(_ service: PracticeSequencerPlaybackServiceProtocol) {
        _ = service
    }

    let service = FakeSequencerPlaybackService()
    accept(service)
    let commands = [
        PracticePlaybackCommand(sourceEventID: "note-1", kind: .noteOn(midi: 60, velocity: 87)),
        PracticePlaybackCommand(sourceEventID: "pedal-1", kind: .controlChange(controller: 64, value: 96)),
    ]
    try await service.execute(commands: commands)
    await service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)

    let snapshot = await service.snapshot()
    #expect(snapshot.commands == commands)
    #expect(snapshot.reset == PerformanceTransportReducer.fullResetCommands)
}

@Test
func audioFailureResetsBeforePublishingAndRetryRecovers() async throws {
    let recorder = PracticeAudioEventRecorder()
    let failureGate = PracticeAudioFailureGate()
    let diagnostics = InMemoryDiagnosticsReporter()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(
            configureAudioSession: { try failureGate.failFirstCall() },
            sendMIDIEvent: { _, status, data1, data2 in
                recorder.recordMIDI(status: status, data1: data1, data2: data2)
                return noErr
            }
        ),
        diagnosticsReporter: diagnostics,
        stateHandler: recorder.record(state:)
    )

    let firstError = await capturedAudioError {
        try await service.warmUp()
    }
    #expect(firstError?.operation == .audioSessionConfiguration)
    #expect(firstError?.recovery == .recoverable)

    let failedEntries = recorder.snapshot()
    let failedStateIndex = failedEntries.firstIndex {
        if case .state(.failed) = $0 { return true }
        return false
    }
    #expect(failedStateIndex != nil)
    if let failedStateIndex {
        let resetControllers = failedEntries[..<failedStateIndex].compactMap { entry -> UInt32? in
            guard case let .midi(_, controller, _) = entry else { return nil }
            return controller
        }
        #expect(resetControllers == [64, 66, 67, 123, 120])
    }

    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)
    let events = await waitForAudioLifecycleDiagnostics(diagnostics, count: 2)
    #expect(events.contains { event in
        event.reason.contains("outcome=failed")
            && event.reason.contains("operation=audioSessionConfiguration")
            && event.reason.contains("reset=succeeded")
    })
    #expect(events.contains { event in
        event.reason.contains("outcome=succeeded")
            && event.reason.contains("operation=audioSessionConfiguration")
    })
}

@Test
func engineSequenceAndRenderFailuresKeepTheirStructuredOperation() async throws {
    let engineService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(startEngine: { _ in throw InjectedPracticeAudioFailure() })
    )
    let engineError = await capturedAudioError {
        try await engineService.warmUp()
    }
    #expect(engineError?.operation == .engineStart)
    #expect(engineError?.recovery == .recoverable)

    let loadService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(
            loadSequence: { _, _ in throw InjectedPracticeAudioFailure() }
        )
    )
    try await loadService.warmUp()
    let loadError = await capturedAudioError {
        try await loadService.load(sequence: emptyPracticeSequence())
    }
    #expect(loadError?.operation == .sequenceLoad)

    let startService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(
            startSequence: { _ in throw InjectedPracticeAudioFailure() }
        )
    )
    try await startService.warmUp()
    try await startService.load(sequence: emptyPracticeSequence())
    let startError = await capturedAudioError {
        try await startService.play(fromSeconds: 0)
    }
    #expect(startError?.operation == .sequenceStart)

    let renderService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(
            sendMIDIEvent: { _, status, _, _ in
                status & 0xF0 == 0xC0 ? -1 : noErr
            }
        )
    )
    try await renderService.warmUp()
    let renderError = await capturedAudioError {
        try await renderService.execute(commands: [
            PracticePlaybackCommand(
                sourceEventID: "program-1",
                kind: .programChange(program: 8)
            ),
        ])
    }
    #expect(renderError?.operation == .commandRender)
}

@Test
func stopAttemptsEveryResetCommandAndPublishesResetFailure() async throws {
    let recorder = PracticeAudioEventRecorder()
    let diagnostics = InMemoryDiagnosticsReporter()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(
            sendMIDIEvent: { _, status, data1, data2 in
                recorder.recordMIDI(status: status, data1: data1, data2: data2)
                return data1 == 64 ? -1 : noErr
            }
        ),
        diagnosticsReporter: diagnostics,
        stateHandler: recorder.record(state:)
    )
    try await service.warmUp()
    recorder.removeAll()

    await service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)

    let entries = recorder.snapshot()
    let controllers = entries.compactMap { entry -> UInt32? in
        guard case let .midi(_, controller, _) = entry else { return nil }
        return controller
    }
    #expect(controllers == [64, 66, 67, 123, 120])
    #expect(await service.currentPlaybackState() == .failed(
        .operationFailed(
            operation: .transportReset,
            recovery: .recoverable,
            detail: "MusicDeviceMIDIEvent failed: -1"
        )
    ))
    let events = await waitForAudioLifecycleDiagnostics(diagnostics, count: 1)
    #expect(events.contains { event in
        event.reason.contains("operation=transportReset")
            && event.reason.contains("reset=failed")
    })
    let metricEvents = await waitForPracticeOutputMetrics(diagnostics)
    #expect(metricEvents.contains { event in
        event.reason.contains("capability=localSampler")
            && event.reason.contains("resetFailed=1")
            && event.reason.contains("stuckNotePrevention=1")
    })
    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)
}

@Test
func interruptionRouteAndMediaResetRequireResetBeforeRecovery() async throws {
    let recorder = PracticeAudioEventRecorder()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: makeAudioPlatform(
            sendMIDIEvent: { _, status, data1, data2 in
                recorder.recordMIDI(status: status, data1: data1, data2: data2)
                return noErr
            }
        ),
        stateHandler: recorder.record(state:)
    )
    try await service.warmUp()
    recorder.removeAll()

    await service.handleAudioSessionEvent(
        .interruptionBegan(reason: .interruptionRouteDisconnected)
    )
    #expect(await service.currentPlaybackState() == .failed(
        .operationFailed(
            operation: .interruption,
            recovery: .recoverable,
            detail: "Audio session interrupted"
        )
    ))
    #expect(recorder.resetControllersBeforeLastState() == [64, 66, 67, 123, 120])

    let blockedError = await capturedAudioError {
        try await service.execute(commands: [
            PracticePlaybackCommand(sourceEventID: "blocked", kind: .noteOn(midi: 60, velocity: 80)),
        ])
    }
    #expect(blockedError?.operation == .interruption)

    await service.handleAudioSessionEvent(.interruptionEnded(shouldResume: true))
    #expect(await service.currentPlaybackState() == .ready)

    recorder.removeAll()
    await service.handleAudioSessionEvent(.routeChanged(reason: .routeOldDeviceUnavailable))
    #expect(await service.currentPlaybackState() == .failed(
        .operationFailed(
            operation: .routeChange,
            recovery: .recoverable,
            detail: "Audio route changed"
        )
    ))
    #expect(recorder.resetControllersBeforeLastState() == [64, 66, 67, 123, 120])
    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)

    recorder.removeAll()
    await service.handleAudioSessionEvent(.mediaServicesReset)
    #expect(await service.currentPlaybackState() == .failed(
        .operationFailed(
            operation: .mediaServicesReset,
            recovery: .recoverable,
            detail: "Audio media services restarted"
        )
    ))
    #expect(recorder.resetControllersBeforeLastState() == [64, 66, 67, 123, 120])
    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)
}

@Test
func missingSoundFontPublishesUnrecoverableFailure() async {
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "MissingSoundFont",
        platform: makeAudioPlatform(resolveSoundFontURL: { _ in nil })
    )
    let error = await capturedAudioError {
        try await service.warmUp()
    }
    #expect(error?.operation == .soundFontLoad)
    #expect(error?.recovery == .unrecoverable)
}

private struct InjectedPracticeAudioFailure: Error {}

private final class PracticeAudioFailureGate: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: true)

    func failFirstCall() throws {
        let shouldFail = lock.withLock { isFirstCall in
            defer { isFirstCall = false }
            return isFirstCall
        }
        if shouldFail {
            throw InjectedPracticeAudioFailure()
        }
    }
}

private final class PracticeAudioEventRecorder: Sendable {
    enum Entry: Equatable {
        case midi(status: UInt32, data1: UInt32, data2: UInt32)
        case state(PracticeAudioPlaybackState)
    }

    private let lock = OSAllocatedUnfairLock(initialState: [Entry]())

    func recordMIDI(status: UInt32, data1: UInt32, data2: UInt32) {
        lock.withLock { $0.append(.midi(status: status, data1: data1, data2: data2)) }
    }

    func record(state: PracticeAudioPlaybackState) {
        lock.withLock { $0.append(.state(state)) }
    }

    func snapshot() -> [Entry] {
        lock.withLock { $0 }
    }

    func removeAll() {
        lock.withLock { $0.removeAll(keepingCapacity: true) }
    }

    func resetControllersBeforeLastState() -> [UInt32] {
        let entries = snapshot()
        guard let stateIndex = entries.lastIndex(where: {
            if case .state = $0 { return true }
            return false
        }) else { return [] }
        return entries[..<stateIndex].compactMap { entry in
            guard case let .midi(_, data1, _) = entry else { return nil }
            return data1
        }
    }
}

private func makeAudioPlatform(
    resolveSoundFontURL: @escaping @Sendable (String) -> URL? = { _ in
        URL(fileURLWithPath: "/tmp/TestSoundFont.sf2")
    },
    configureAudioSession: @escaping @Sendable () throws -> Void = {},
    loadSoundBank: @escaping @Sendable (AVAudioUnitSampler, URL, UInt8) throws -> Void = { _, _, _ in },
    startEngine: @escaping @Sendable (AVAudioEngine) throws -> Void = { _ in },
    loadSequence: @escaping @Sendable (AVAudioSequencer, Data) throws -> Void = { _, _ in },
    startSequence: @escaping @Sendable (AVAudioSequencer) throws -> Void = { _ in },
    sendMIDIEvent: @escaping @Sendable (AudioUnit, UInt32, UInt32, UInt32) -> OSStatus = { _, _, _, _ in noErr }
) -> PracticeAudioPlatformOperations {
    PracticeAudioPlatformOperations(
        resolveSoundFontURL: resolveSoundFontURL,
        configureAudioSession: configureAudioSession,
        loadSoundBank: loadSoundBank,
        startEngine: startEngine,
        loadSequence: loadSequence,
        startSequence: startSequence,
        sendMIDIEvent: sendMIDIEvent
    )
}

private func emptyPracticeSequence() -> PracticeSequencerSequence {
    PracticeSequencerSequence(
        midiData: Data(),
        durationSeconds: 0,
        events: []
    )
}

private func capturedAudioError(
    _ operation: () async throws -> Void
) async -> PracticeAudioError? {
    do {
        try await operation()
        Issue.record("Expected PracticeAudioError")
        return nil
    } catch let error as PracticeAudioError {
        return error
    } catch {
        Issue.record("Unexpected error: \(error)")
        return nil
    }
}

private func waitForAudioLifecycleDiagnostics(
    _ reporter: InMemoryDiagnosticsReporter,
    count: Int
) async -> [DiagnosticEvent] {
    for _ in 0 ..< 100 {
        let events = await reporter.events.filter { $0.stage == PianoPerformanceDiagnosticStage.playback.rawValue }
        if events.count >= count { return events }
        await Task.yield()
    }
    return await reporter.events.filter { $0.stage == PianoPerformanceDiagnosticStage.playback.rawValue }
}

private func waitForPracticeOutputMetrics(
    _ reporter: InMemoryDiagnosticsReporter
) async -> [DiagnosticEvent] {
    for _ in 0 ..< 100 {
        let events = await reporter.events.filter { $0.stage == "playback.outputMetrics" }
        if events.isEmpty == false { return events }
        await Task.yield()
    }
    return await reporter.events.filter { $0.stage == "playback.outputMetrics" }
}
