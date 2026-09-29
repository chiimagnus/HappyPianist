import Foundation
import MIDI
import Practice
@testable import HappyPianistAVP
import Testing

@MainActor
private final class TakeoverDiscoveryOrchestrator: ImprovBackendDiscoveryOrchestrating {
    func start(for _: ImprovBackendKind) {}
    func stopAll() {}
}

@MainActor
private final class TakeoverPracticeSession: AIPerformancePracticeSessionProtocol {
    let settingsProvider: any PracticeSessionSettingsProviderProtocol = TakeoverSettingsProvider()
    func refreshAudioRecognitionForCurrentState() {}
}

@MainActor
private struct TakeoverSettingsProvider: PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode { .step }
    var practiceHandMode: PracticeHandMode { .both }
    var soundRoutingSettings: PracticeSoundRoutingSettings {
        .init(outputRoute: .localSampler, midiDestinationUniqueID: nil, sendLocalControlOff: false)
    }
}

private actor TakeoverGenerationBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .localRule
    nonisolated let displayName = "Takeover generation fake"

    private var callCountValue = 0

    func generateCreativeResponse(
        phrase _: CreativeDuetPhrase,
        generation: CreativeDuetGeneration
    ) async throws -> CreativeDuetResponse {
        callCountValue += 1
        return CreativeDuetResponse(
            schedule: [
                PracticeSequencerMIDIEvent(timeSeconds: 0, kind: .noteOn(midi: 72, velocity: 88)),
                PracticeSequencerMIDIEvent(timeSeconds: 0.2, kind: .noteOff(midi: 72)),
            ],
            provider: kind,
            generation: generation,
            provenance: .backendGenerated(latencyMS: nil)
        )
    }

    func callCount() -> Int { callCountValue }
}

private actor TakeoverCompanionBackend: CompanionDecisionBackendProtocol {
    struct Call: Sendable {
        let input: CompanionDecisionInput
        let action: CompanionAction
    }

    nonisolated let kind: CompanionDecisionBackendKind = .ruleBased
    nonisolated let displayName = "Takeover companion fake"

    private var action: CompanionAction = .support
    private var calls: [Call] = []
    private var blockPostStartDecision = false
    private var blockedPostStartDecision = false
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func decide(_ input: CompanionDecisionInput) async throws -> CompanionDecision {
        let currentAction = action
        calls.append(Call(input: input, action: currentAction))
        if blockPostStartDecision,
           input.isAIPlaybackActive,
           input.userNoteOnSinceAIPlaybackStarted
        {
            blockPostStartDecision = false
            blockedPostStartDecision = true
            blockedWaiters.forEach { $0.resume() }
            blockedWaiters.removeAll()
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
            blockedPostStartDecision = false
        }
        return CompanionDecision(action: currentAction)
    }

    func setAction(_ action: CompanionAction) {
        self.action = action
    }

    func armPostStartDecisionBlock() {
        blockPostStartDecision = true
    }

    func waitUntilPostStartDecisionIsBlocked() async {
        guard blockedPostStartDecision == false else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releasePostStartDecision() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func recordedCalls() -> [Call] { calls }
}

@MainActor
private final class HoldingTakeoverPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var warmUpCallCount = 0
    private(set) var loadCallCount = 0
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isPlaying = false

    func warmUp() throws { warmUpCallCount += 1 }

    func stop(resetCommands _: [PerformanceTransportCommand]) {
        stopCallCount += 1
        isPlaying = false
    }

    func load(sequence _: PracticeSequencerSequence) throws { loadCallCount += 1 }

    func play(fromSeconds _: TimeInterval) throws {
        playCallCount += 1
        isPlaying = true
    }

    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

@Test
@MainActor
func companionPlaybackPolicyPreservesCurrentAudioUntilExplicitYield() async throws {
    var nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []
    let generationBackend = TakeoverGenerationBackend()
    let companionBackend = TakeoverCompanionBackend()
    let playbackService = HoldingTakeoverPlaybackService()
    let playbackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in try? await Task.sleep(for: .milliseconds(1)) },
        discoveryOrchestrator: TakeoverDiscoveryOrchestrator(),
        backendRegistry: .init(backends: [generationBackend]),
        selectedBackendKind: { .localRule },
        aiPlaybackServiceFactory: { playbackFactory },
        companionDecisionBackendRegistry: .init(backends: [companionBackend]),
        selectedCompanionDecisionBackendKind: { .ruleBased },
        onStateChanged: { states.append($0) }
    )
    defer { service.setEnabled(false) }

    let session = TakeoverPracticeSession()
    service.updatePracticeSession(session)
    service.setEnabled(true)
    recordUserMIDI(.noteOn(note: 60, velocity: 90), at: 0, service: service)
    nowUptime = 0.3

    await TestAsyncWait.until("AI playback starts") {
        await MainActor.run { states.last?.isAIPlaybackActive == true && playbackService.isPlaying }
    }
    await TestAsyncWait.until("post-start Companion state resets reentry") {
        let calls = await companionBackend.recordedCalls()
        return calls.contains {
            $0.input.isAIPlaybackActive && $0.input.userNoteOnSinceAIPlaybackStarted == false
        }
    }

    let callsBeforeSystemPlayback = await companionBackend.recordedCalls().count
    service.recordPerformanceObservationForPhraseRecordingIfNeeded(
        PerformanceObservation(
            source: .init(
                kind: .midi1,
                id: "takeover-system-playback",
                generation: 1,
                role: .systemPlayback
            ),
            timing: .init(
                host: .init(seconds: 0.31),
                source: nil,
                correctedHost: .init(seconds: 0.31),
                mapping: nil,
                provenance: .hostOnly
            ),
            event: .noteOn(note: 76, velocity: .init(midi1: 80))
        )
    )
    await TestAsyncWait.until("Companion ticks after system playback") {
        await companionBackend.recordedCalls().count > callsBeforeSystemPlayback
    }
    #expect(await companionBackend.recordedCalls().last?.input.userNoteOnSinceAIPlaybackStarted == false)

    nowUptime = 0.35
    recordUserMIDI(.noteOff(note: 60, velocity: 0), at: 0.35, service: service)
    await TestAsyncWait.until("Companion observes note-off without reentry") {
        let calls = await companionBackend.recordedCalls()
        return calls.last?.input.lastUserEventTimestampSeconds == 0.35
    }
    #expect(await companionBackend.recordedCalls().last?.input.userNoteOnSinceAIPlaybackStarted == false)

    let stopCountBeforeReentry = playbackService.stopCallCount
    await companionBackend.armPostStartDecisionBlock()
    nowUptime = 0.4
    recordUserMIDI(.noteOn(note: 64, velocity: 92), at: 0.4, service: service)
    await companionBackend.waitUntilPostStartDecisionIsBlocked()

    #expect(states.last?.isAIPlaybackActive == true)
    #expect(playbackService.isPlaying)
    #expect(playbackService.stopCallCount == stopCountBeforeReentry)

    await companionBackend.releasePostStartDecision()
    await TestAsyncWait.until("Companion observes post-start user note-on") {
        let calls = await companionBackend.recordedCalls()
        return calls.contains {
            $0.input.isAIPlaybackActive && $0.input.userNoteOnSinceAIPlaybackStarted
        }
    }
    #expect(playbackService.stopCallCount == stopCountBeforeReentry)

    await companionBackend.setAction(.listen)
    await TestAsyncWait.until("listen decision is consumed") {
        await companionBackend.recordedCalls().contains { $0.action == .listen }
    }
    #expect(states.last?.isAIPlaybackActive == true)
    #expect(playbackService.isPlaying)
    #expect(playbackService.stopCallCount == stopCountBeforeReentry)

    await companionBackend.setAction(.yield)
    await TestAsyncWait.until("yield stops current playback") {
        await MainActor.run {
            states.last?.isAIPlaybackActive == false && playbackService.isPlaying == false
        }
    }
    #expect(playbackService.stopCallCount > stopCountBeforeReentry)
}

@MainActor
private func recordUserMIDI(
    _ kind: MIDI1InputEvent.Kind,
    at timestamp: TimeInterval,
    service: AIPerformanceService
) {
    service.recordMIDI1EventForPhraseRecordingIfNeeded(
        MIDI1InputEvent(
            kind: kind,
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .endpointUniqueID(700), endpointName: "takeover-test"),
            receivedAt: Date(timeIntervalSince1970: timestamp),
            receivedAtUptimeSeconds: timestamp
        )
    )
}

private actor TakeoverWarmUpGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func block() async {
        didStart = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitForStart() async {
        guard didStart == false else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class PreparingTakeoverPlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private let warmUpGate: TakeoverWarmUpGate
    private(set) var playCallCount = 0

    init(warmUpGate: TakeoverWarmUpGate) {
        self.warmUpGate = warmUpGate
    }

    func warmUp() async throws {
        await warmUpGate.block()
    }

    func stop(resetCommands _: [PerformanceTransportCommand]) {}
    func load(sequence _: PracticeSequencerSequence) throws {}
    func play(fromSeconds _: TimeInterval) throws { playCallCount += 1 }
    func currentSeconds() -> TimeInterval { 0 }
    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) throws {}
    func execute(commands _: [PracticePlaybackCommand]) throws {}
    func stopAllLiveNotes() {}
}

@Test
@MainActor
func preparingPlaybackKeepsUIBusyWithoutReportingCompanionPlaybackActive() async {
    var nowUptime: TimeInterval = 0
    var states: [AIPerformanceService.State] = []
    let generationBackend = TakeoverGenerationBackend()
    let companionBackend = TakeoverCompanionBackend()
    let warmUpGate = TakeoverWarmUpGate()
    let playbackService = PreparingTakeoverPlaybackService(warmUpGate: warmUpGate)
    let playbackFactory = DuetAIPlaybackServiceFactory(
        makeLocalSamplerPlaybackService: { playbackService },
        makeExternalMIDIPlaybackService: { _ in playbackService }
    )
    let service = AIPerformanceService(
        nowUptimeSeconds: { nowUptime },
        sleepFor: { _ in try? await Task.sleep(for: .milliseconds(1)) },
        discoveryOrchestrator: TakeoverDiscoveryOrchestrator(),
        backendRegistry: .init(backends: [generationBackend]),
        selectedBackendKind: { .localRule },
        aiPlaybackServiceFactory: { playbackFactory },
        companionDecisionBackendRegistry: .init(backends: [companionBackend]),
        selectedCompanionDecisionBackendKind: { .ruleBased },
        onStateChanged: { states.append($0) }
    )
    defer { service.setEnabled(false) }

    let session = TakeoverPracticeSession()
    service.updatePracticeSession(session)
    service.setEnabled(true)
    recordUserMIDI(.noteOn(note: 60, velocity: 90), at: 0, service: service)
    nowUptime = 0.3

    await warmUpGate.waitForStart()
    await TestAsyncWait.until("preparing state is externally visible") {
        await MainActor.run {
            states.last?.isAIPerformanceActive == true
                && states.last?.isAIPlaybackActive == false
        }
    }
    #expect(playbackService.playCallCount == 0)

    let callsBeforeRelease = await companionBackend.recordedCalls()
    #expect(callsBeforeRelease.isEmpty == false)
    #expect(callsBeforeRelease.allSatisfy { $0.input.isAIPlaybackActive == false })

    await warmUpGate.release()
    await TestAsyncWait.until("playback becomes active only after play succeeds") {
        await MainActor.run {
            states.last?.isAIPlaybackActive == true && playbackService.playCallCount == 1
        }
    }
}
