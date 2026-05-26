import Foundation
import Observation
import os

@MainActor
@Observable
final class ARGuideAIPerformanceViewModel {
    let duetDiscoveryService: BonjourBackendDiscoveryService
    private let backendSelection = ImprovBackendSelection()
    private let aiPlaybackServiceFactory: @MainActor () -> DuetAIPlaybackServiceFactory
    @ObservationIgnored
    private let localCoreMLModelLoader = PerformanceRNNCoreMLModelLoader()

    var localCoreMLDuetAvailability: LocalCoreMLDuetAvailability = .idle

    var isVirtualPerformerEnabled = false
    var isAIPerformanceActive = false
    var isAIGenerating = false
    var isAIPlaybackActive = false
    var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] = []
    var lastImprovStatusText: String?

    @ObservationIgnored
    private lazy var aiPerformanceService: AIPerformanceService = .init(
        logger: Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
            category: "AIPerformanceService"
        ),
        discoveryOrchestrator: ImprovBackendDiscoveryOrchestrator(
            servicesByKind: [
                .networkBonjourHTTPDuet: duetDiscoveryService,
            ]
        ),
        backendRegistry: makeBackendRegistry(),
        selectedBackendKind: { [backendSelection] in
            backendSelection.selectedKind()
        },
        aiPlaybackServiceFactory: { [aiPlaybackServiceFactory] in
            aiPlaybackServiceFactory()
        },
        onStateChanged: { [weak self] state in
            guard let self else { return }
            isAIPerformanceActive = state.isAIPerformanceActive
            isAIGenerating = state.isAIGenerating
            isAIPlaybackActive = state.isAIPlaybackActive
            latestAIPerformanceSchedule = state.latestSchedule
            lastImprovStatusText = state.lastImprovStatusText
        }
    )

    init(
        duetDiscoveryService: BonjourBackendDiscoveryService? = nil,
        aiPlaybackServiceFactory: (@MainActor () -> DuetAIPlaybackServiceFactory)? = nil
    ) {
        self.duetDiscoveryService = duetDiscoveryService ?? BonjourBackendDiscoveryService(
            serviceType: "_lpduet._tcp",
            requiredTXTRecord: [
                "path": "/generate",
                "protocol_version": "1",
                "engine": "magenta",
            ]
        )
        if let aiPlaybackServiceFactory {
            self.aiPlaybackServiceFactory = aiPlaybackServiceFactory
        } else {
            let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            let factory = DuetAIPlaybackServiceFactory(
                makeLocalSamplerPlaybackService: {
                    let service: any PracticeSequencerPlaybackServiceProtocol =
                        isRunningUnitTests
                            ? NoopPracticeSequencerPlaybackService()
                            : AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2", channel: 1)
                    return service
                },
                makeExternalMIDIPlaybackService: { destinationUniqueID in
                    let service: any PracticeSequencerPlaybackServiceProtocol =
                        isRunningUnitTests
                            ? NoopPracticeSequencerPlaybackService()
                            : CoreMIDIPracticePlaybackService(destinationUniqueID: destinationUniqueID, channel: 1)
                    return service
                }
            )
            self.aiPlaybackServiceFactory = { factory }
        }
    }

    var backendStatusText: String? {
        switch backendSelection.selectedKind() {
        case .networkBonjourHTTPDuet:
            return backendDiscoveryStatusText(
                backendName: "A.I. Duet",
                state: duetDiscoveryService.state,
                notFoundHint: "请先在电脑端启动 Duet Python 服务（默认端口 8766）。"
            )
        case .localCoreMLDuet:
            startLocalCoreMLDuetProbeIfNeeded()
            return localCoreMLDuetAvailability.statusText()
        case .localRule:
            return "后端：本地规则生成（无需电脑端服务）"
        case .tickRangeReplay:
            return "后端：按谱片段回放（无需电脑端服务）"
        }
    }

    func restartDiscoveryForSelectedBackend() {
        switch backendSelection.selectedKind() {
        case .networkBonjourHTTPDuet:
            duetDiscoveryService.stop()
            duetDiscoveryService.start()
        case .localCoreMLDuet:
            restartLocalCoreMLDuetProbe()
        case .localRule, .tickRangeReplay:
            break
        }
    }

    func updatePracticeSession(_ practiceSessionViewModel: PracticeSessionViewModel) {
        aiPerformanceService.updatePracticeSession(practiceSessionViewModel)
    }

    func setVirtualPerformerEnabled(_ isEnabled: Bool, practiceSessionViewModel: PracticeSessionViewModel) {
        isVirtualPerformerEnabled = isEnabled
        aiPerformanceService.updatePracticeSession(practiceSessionViewModel)
        aiPerformanceService.setEnabled(isEnabled)
    }

    #if DEBUG
        func debugInjectImprovTestPhraseIfPossible() {
            guard isVirtualPerformerEnabled else { return }

            let baseUptime = ProcessInfo.processInfo.systemUptime
            let baseDate = Date.now
            let source = MIDI1InputEvent.Source(
                identifier: .sourceIndex(-1),
                endpointName: "DEBUG"
            )

            // A short phrase: C4-E4-G4, then release. This should trigger DuetTurnTakingCore's
            // short-phrase send ~600ms after release.
            let chord: [(note: Int, velocity: Int)] = [(60, 90), (64, 85), (67, 88)]

            for (index, item) in chord.enumerated() {
                recordMIDI1EventForPhraseRecordingIfNeeded(
                    MIDI1InputEvent(
                        kind: .noteOn(note: item.note, velocity: item.velocity),
                        channel: 1,
                        group: 0,
                        source: source,
                        receivedAt: baseDate,
                        receivedAtUptimeSeconds: baseUptime + Double(index) * 0.04,
                        debugEventID: Int64(10_000 + index)
                    )
                )
            }

            for (index, item) in chord.enumerated() {
                recordMIDI1EventForPhraseRecordingIfNeeded(
                    MIDI1InputEvent(
                        kind: .noteOff(note: item.note, velocity: 0),
                        channel: 1,
                        group: 0,
                        source: source,
                        receivedAt: baseDate,
                        receivedAtUptimeSeconds: baseUptime + 0.30 + Double(index) * 0.04,
                        debugEventID: Int64(20_000 + index)
                    )
                )
            }
        }
    #endif

    func recordMIDI1EventForPhraseRecordingIfNeeded(_ event: MIDI1InputEvent) {
        aiPerformanceService.recordMIDI1EventForPhraseRecordingIfNeeded(event)
    }

    func recordMIDI2EventForPhraseRecordingIfNeeded(_ event: MIDI2InputEvent) {
        aiPerformanceService.recordMIDI2EventForPhraseRecordingIfNeeded(event)
    }

    func recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: Bool,
        keyContact: KeyContactResult,
        nowUptimeSeconds: TimeInterval
    ) {
        aiPerformanceService.recordKeyContactForPhraseRecordingIfNeeded(
            usesBluetoothMIDIInput: usesBluetoothMIDIInput,
            keyContact: keyContact,
            nowUptimeSeconds: nowUptimeSeconds
        )
    }

    func shutdown() {
        // NOTE: ARGuideViewModel lives for the app lifetime, and immersive spaces may disappear/re-appear.
        // We must not permanently "shutdown" the AIPerformanceService here, otherwise it cannot be re-enabled
        // after returning to practice. Treat this as a reversible teardown.
        aiPerformanceService.setEnabled(false)
    }

    private func makeBackendRegistry() -> ImprovBackendRegistry {
        ImprovBackendRegistry(
            backends: [
                DuetNetworkBonjourHTTPImprovBackend(discoveryService: duetDiscoveryService),
                LocalCoreMLDuetImprovBackend(modelLoader: localCoreMLModelLoader),
                LocalRuleImprovBackend(),
                TickRangeReplayImprovBackend(),
            ]
        )
    }

    @ObservationIgnored
    private var localCoreMLDuetProbeTask: Task<Void, Never>?

    private func restartLocalCoreMLDuetProbe() {
        localCoreMLDuetProbeTask?.cancel()
        localCoreMLDuetProbeTask = nil
        localCoreMLDuetAvailability = .idle
        startLocalCoreMLDuetProbeIfNeeded()
    }

    private func startLocalCoreMLDuetProbeIfNeeded() {
        guard localCoreMLDuetProbeTask == nil else { return }

        let expectedNames = [
            "AIDuetPerformanceRNN.mlmodelc",
            "AIDuetPerformanceRNN.mlpackage",
        ]

        let hasCompiledInBundle = Bundle.main.url(forResource: "AIDuetPerformanceRNN", withExtension: "mlmodelc") != nil
        let hasPackageInBundle = Bundle.main.url(forResource: "AIDuetPerformanceRNN", withExtension: "mlpackage") != nil
        guard hasCompiledInBundle || hasPackageInBundle else {
            localCoreMLDuetAvailability = .missing(expectedNames: expectedNames)
            return
        }

        localCoreMLDuetAvailability = .probing
        let loader = localCoreMLModelLoader

        localCoreMLDuetProbeTask = Task.detached(priority: .utility) { [weak self] in
            let resolvedAvailability: LocalCoreMLDuetAvailability?
            do {
                _ = try await loader.loadStepModel()
                resolvedAvailability = .available
            } catch is CancellationError {
                resolvedAvailability = nil
            } catch let error as PerformanceRNNCoreMLModelLoaderError {
                switch error {
                case let .modelMissing(expectedNames):
                    resolvedAvailability = .missing(expectedNames: expectedNames)
                case let .compileFailed(_, message), let .loadFailed(_, message):
                    resolvedAvailability = .failed(message: message)
                }
            } catch {
                resolvedAvailability = .failed(message: "Unknown error.")
            }

            guard Task.isCancelled == false else {
                await MainActor.run {
                    self?.localCoreMLDuetProbeTask = nil
                }
                return
            }

            if let resolvedAvailability {
                await MainActor.run {
                    self?.localCoreMLDuetAvailability = resolvedAvailability
                }
            }

            await MainActor.run {
                self?.localCoreMLDuetProbeTask = nil
            }
        }
    }

    private func backendDiscoveryStatusText(
        backendName: String,
        state: BonjourBackendDiscoveryService.State,
        notFoundHint: String
    ) -> String {
        switch state {
        case .idle:
            return "后端：\(backendName)（未开始发现）"
        case .discovering:
            return "后端：\(backendName)（正在发现…）若长时间找不到，\(notFoundHint)"
        case let .resolved(host, port, txtRecord):
            let engine = txtRecord["engine"]
            let engineImpl = txtRecord["engine_impl"]
            let details: String = {
                var parts: [String] = []
                if let engine, engine.isEmpty == false { parts.append("engine=\(engine)") }
                if let engineImpl, engineImpl.isEmpty == false { parts.append("impl=\(engineImpl)") }
                return parts.isEmpty ? "" : " \(parts.joined(separator: " "))"
            }()
            return "后端：\(backendName)（已找到 \(host):\(port)\(details)）"
        case let .failed(message):
            return "后端：\(backendName)（发现失败：\(message)）"
        case .denied:
            return "后端：\(backendName)（Local Network 权限被拒）请到系统设置开启后重试。"
        }
    }
}

enum LocalCoreMLDuetAvailability: Sendable, Equatable {
    case idle
    case probing
    case available
    case missing(expectedNames: [String])
    case failed(message: String)

    func statusText() -> String {
        switch self {
        case .idle, .probing:
            "后端：本地 CoreML（检测中…首次加载可能需要编译模型）"
        case .available:
            "后端：本地 CoreML（可用）"
        case let .missing(expectedNames):
            "后端：本地 CoreML（缺少模型文件：\(expectedNames.joined(separator: " / "))）请将模型添加到 App bundle 后重试。"
        case let .failed(message):
            "后端：本地 CoreML（加载失败：\(message)）可尝试重新放置模型文件或重启后端。"
        }
    }
}

@MainActor
private final class ImprovBackendDiscoveryOrchestrator: ImprovBackendDiscoveryOrchestrating {
    private let servicesByKind: [ImprovBackendKind: any BonjourBackendDiscoveryServiceProtocol]

    init(servicesByKind: [ImprovBackendKind: any BonjourBackendDiscoveryServiceProtocol]) {
        self.servicesByKind = servicesByKind
    }

    func start(for kind: ImprovBackendKind) {
        var didStart = false
        for (mappedKind, service) in servicesByKind {
            if mappedKind == kind {
                service.start()
                didStart = true
            } else {
                service.stop()
            }
        }

        if didStart == false {
            stopAll()
        }
    }

    func stopAll() {
        for service in servicesByKind.values {
            service.stop()
        }
    }
}
