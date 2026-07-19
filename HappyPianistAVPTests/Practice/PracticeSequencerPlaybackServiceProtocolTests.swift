import Foundation
@testable import HappyPianistAVP
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
    let output = FakePerformanceOutput(capabilities: .localSampler)
    output.failNextAudioOperation(.audioSessionConfiguration)
    let diagnostics = InMemoryDiagnosticsReporter()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform(),
        diagnosticsReporter: diagnostics,
        stateHandler: output.record(state:)
    )

    let firstError = await capturedAudioError {
        try await service.warmUp()
    }
    #expect(firstError?.operation == .audioSessionConfiguration)
    #expect(firstError?.recovery == .recoverable)

    let failedEntries = output.audioEntriesSnapshot()
    let failedStateIndex = failedEntries.firstIndex {
        if case .state(.failed) = $0 { return true }
        return false
    }
    #expect(failedEntries.first == .sequenceStopped)
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
    let engineOutput = FakePerformanceOutput(capabilities: .localSampler)
    engineOutput.failNextAudioOperation(.engineStart)
    let engineService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: engineOutput.makeAudioPlatform()
    )
    let engineError = await capturedAudioError {
        try await engineService.warmUp()
    }
    #expect(engineError?.operation == .engineStart)
    #expect(engineError?.recovery == .recoverable)

    let loadOutput = FakePerformanceOutput(capabilities: .localSampler)
    loadOutput.failNextAudioOperation(.sequenceLoad)
    let loadService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: loadOutput.makeAudioPlatform()
    )
    try await loadService.warmUp()
    let loadError = await capturedAudioError {
        try await loadService.load(sequence: emptyPracticeSequence())
    }
    #expect(loadError?.operation == .sequenceLoad)

    let startOutput = FakePerformanceOutput(capabilities: .localSampler)
    startOutput.failNextAudioOperation(.sequenceStart)
    let startService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: startOutput.makeAudioPlatform()
    )
    try await startService.warmUp()
    try await startService.load(sequence: emptyPracticeSequence())
    let startError = await capturedAudioError {
        try await startService.play(fromSeconds: 0)
    }
    #expect(startError?.operation == .sequenceStart)

    let renderOutput = FakePerformanceOutput(capabilities: .localSampler)
    renderOutput.setFailingAudioStatusKinds([0xC0])
    let renderService = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: renderOutput.makeAudioPlatform()
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
    let output = FakePerformanceOutput(capabilities: .localSampler)
    output.setFailingAudioControllers([64])
    let diagnostics = InMemoryDiagnosticsReporter()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform(),
        diagnosticsReporter: diagnostics,
        stateHandler: output.record(state:)
    )
    try await service.warmUp()
    output.removeAllAudioEntries()

    await service.stop(resetCommands: PerformanceTransportReducer.fullResetCommands)

    let entries = output.audioEntriesSnapshot()
    #expect(entries.first == .sequenceStopped)
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
            && event.reason.contains("stuckNotePrevention=0")
    })
    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)
}

@Test
func interruptionRouteAndMediaResetRequireResetBeforeRecovery() async throws {
    let output = FakePerformanceOutput(capabilities: .localSampler)
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform(),
        stateHandler: output.record(state:)
    )
    #expect(output.audioOperationCount(.audioGraphCreation) == 1)
    try await service.warmUp()
    output.removeAllAudioEntries()

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
    #expect(output.resetControllersBeforeLastAudioState() == [64, 66, 67, 123, 120])

    let blockedError = await capturedAudioError {
        try await service.execute(commands: [
            PracticePlaybackCommand(sourceEventID: "blocked", kind: .noteOn(midi: 60, velocity: 80)),
        ])
    }
    #expect(blockedError?.operation == .interruption)

    await service.handleAudioSessionEvent(.interruptionEnded(shouldResume: true))
    #expect(await service.currentPlaybackState() == .ready)

    output.removeAllAudioEntries()
    await service.handleAudioSessionEvent(.routeChanged(reason: .routeOldDeviceUnavailable))
    #expect(await service.currentPlaybackState() == .failed(
        .operationFailed(
            operation: .routeChange,
            recovery: .recoverable,
            detail: "Audio route changed"
        )
    ))
    #expect(output.resetControllersBeforeLastAudioState() == [64, 66, 67, 123, 120])
    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)

    output.removeAllAudioEntries()
    await service.handleAudioSessionEvent(.mediaServicesReset)
    #expect(output.audioOperationCount(.audioGraphCreation) == 2)
    #expect(await service.currentPlaybackState() == .failed(
        .operationFailed(
            operation: .mediaServicesReset,
            recovery: .recoverable,
            detail: "Audio media services restarted"
        )
    ))
    #expect(output.resetControllersBeforeLastAudioState() == [64, 66, 67, 123, 120])
    try await service.warmUp()
    #expect(await service.currentPlaybackState() == .ready)
}

@Test
func missingSoundFontPublishesUnrecoverableFailure() async {
    let output = FakePerformanceOutput(capabilities: .localSampler)
    output.setSoundFontAvailable(false)
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "MissingSoundFont",
        platform: output.makeAudioPlatform()
    )
    let error = await capturedAudioError {
        try await service.warmUp()
    }
    #expect(error?.operation == .soundFontLoad)
    #expect(error?.recovery == .unrecoverable)
}

@Test
func playbackServiceTeardownStopsSequenceResetsAndStopsEngine() async throws {
    let output = FakePerformanceOutput(capabilities: .localSampler)
    var service: AVAudioSequencerPracticePlaybackService? = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform()
    )
    try await service?.warmUp()
    output.removeAllAudioEntries()

    service = nil

    #expect(await waitForAudioEntry(output, matching: .engineStopped))
    #expect(output.audioEntriesSnapshot() == [
        .sequenceStopped,
        .midi(status: 0xB0, data1: 64, data2: 0),
        .midi(status: 0xB0, data1: 66, data2: 0),
        .midi(status: 0xB0, data1: 67, data2: 0),
        .midi(status: 0xB0, data1: 123, data2: 0),
        .midi(status: 0xB0, data1: 120, data2: 0),
        .engineStopped,
    ])
}

@Test
func localSamplerReportsSequenceControllerApproximations() async throws {
    let output = FakePerformanceOutput(capabilities: .localSampler)
    let diagnostics = InMemoryDiagnosticsReporter()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform(),
        diagnosticsReporter: diagnostics
    )
    try await service.load(sequence: PracticeSequencerSequence(
        midiData: Data(),
        durationSeconds: 0,
        events: [],
        outputApproximations: [
            PerformanceOutputApproximation(controllerNumber: 64, sourceValue: 96, renderedValue: 127),
            PerformanceOutputApproximation(controllerNumber: 67, sourceValue: 20, renderedValue: 0),
        ]
    ))

    let events = await waitForAudioControllerDiagnostics(diagnostics)
    #expect(events.contains { event in
        event.stage == "audio.controllerCapability"
            && event.reason == "approximationCount=2"
    })
}

@Test
func localSamplerQuantizesLiveControllerAndReportsApproximation() async throws {
    let output = FakePerformanceOutput(capabilities: .localSampler)
    let diagnostics = InMemoryDiagnosticsReporter()
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform(),
        diagnosticsReporter: diagnostics
    )

    try await service.execute(commands: [
        PracticePlaybackCommand(
            sourceEventID: "live-half-pedal",
            kind: .controlChange(controller: 64, value: 96)
        ),
    ])

    #expect(output.audioEntriesSnapshot().contains(
        .midi(status: 0xB0, data1: 64, data2: 127)
    ))
    let events = await waitForAudioControllerDiagnostics(diagnostics)
    #expect(events.contains { event in
        event.stage == "audio.controllerCapability"
            && event.reason == "approximationCount=1"
    })
}

@Test
func readyAudioEngineSkipsRepeatedSessionConfigurationAndRecoversWhenStopped() async throws {
    let output = FakePerformanceOutput(capabilities: .localSampler)
    let service = AVAudioSequencerPracticePlaybackService(
        soundFontResourceName: "TestSoundFont",
        platform: output.makeAudioPlatform()
    )

    try await service.warmUp()
    try await service.load(sequence: emptyPracticeSequence())
    try await service.execute(commands: [
        PracticePlaybackCommand(
            sourceEventID: "live-program",
            kind: .programChange(program: 1)
        ),
    ])

    #expect(output.audioOperationCount(.audioSessionConfiguration) == 1)
    #expect(output.audioOperationCount(.soundBankLoad) == 1)
    #expect(output.audioOperationCount(.engineStart) == 1)

    await service.handleAudioSessionEvent(.routeChanged(reason: .routeOldDeviceUnavailable))
    try await service.warmUp()

    #expect(output.audioOperationCount(.audioSessionConfiguration) == 2)
    #expect(output.audioOperationCount(.soundBankLoad) == 2)
    #expect(output.audioOperationCount(.engineStart) == 2)
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

private func waitForAudioEntry(
    _ output: FakePerformanceOutput,
    matching expected: FakePerformanceOutput.AudioEntry
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while clock.now < deadline {
        if output.audioEntriesSnapshot().contains(expected) { return true }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return output.audioEntriesSnapshot().contains(expected)
        }
    }
    return output.audioEntriesSnapshot().contains(expected)
}

private func waitForAudioControllerDiagnostics(
    _ reporter: InMemoryDiagnosticsReporter
) async -> [DiagnosticEvent] {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while clock.now < deadline {
        let events = await reporter.events.filter { $0.stage == "audio.controllerCapability" }
        if events.isEmpty == false { return events }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return events
        }
    }
    return await reporter.events.filter { $0.stage == "audio.controllerCapability" }
}

private func waitForAudioLifecycleDiagnostics(
    _ reporter: InMemoryDiagnosticsReporter,
    count: Int
) async -> [DiagnosticEvent] {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while clock.now < deadline {
        let events = await reporter.events.filter { $0.stage == PianoPerformanceDiagnosticStage.playback.rawValue }
        if events.count >= count { return events }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return events
        }
    }
    return await reporter.events.filter { $0.stage == PianoPerformanceDiagnosticStage.playback.rawValue }
}

private func waitForPracticeOutputMetrics(
    _ reporter: InMemoryDiagnosticsReporter
) async -> [DiagnosticEvent] {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while clock.now < deadline {
        let events = await reporter.events.filter { $0.stage == "playback.outputMetrics" }
        if events.isEmpty == false { return events }
        do {
            try await Task.sleep(for: .milliseconds(1))
        } catch {
            return events
        }
    }
    return await reporter.events.filter { $0.stage == "playback.outputMetrics" }
}
