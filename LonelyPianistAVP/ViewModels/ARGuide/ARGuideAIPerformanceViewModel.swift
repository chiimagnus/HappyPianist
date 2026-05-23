import Foundation
import Observation
import os

@MainActor
@Observable
final class ARGuideAIPerformanceViewModel {
    let backendDiscoveryService: BonjourBackendDiscoveryService
    private let backendSelection = ImprovBackendSelection()

    var isVirtualPerformerEnabled = false
    var isAIPerformanceActive = false
    var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] = []
    var lastImprovStatusText: String?

    @ObservationIgnored
    private lazy var aiPerformanceService: AIPerformanceService = .init(
        logger: Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
            category: "AIPerformanceService"
        ),
        backendDiscoveryService: backendDiscoveryService,
        backendRegistry: makeBackendRegistry(),
        selectedBackendKind: { [backendSelection] in
            backendSelection.selectedKind()
        },
        onStateChanged: { [weak self] state in
            guard let self else { return }
            isAIPerformanceActive = state.isAIPerformanceActive
            latestAIPerformanceSchedule = state.latestSchedule
            lastImprovStatusText = state.lastImprovStatusText
        }
    )

    init(backendDiscoveryService: BonjourBackendDiscoveryService? = nil) {
        self.backendDiscoveryService = backendDiscoveryService ?? BonjourBackendDiscoveryService()
    }

    var backendStatusText: String? {
        switch backendSelection.selectedKind() {
        case .networkBonjourHTTP:
            switch backendDiscoveryService.state {
            case .idle:
                "Backend: network (idle)"
            case .discovering:
                "Backend: network (discovering)"
            case let .resolved(host, port):
                "Backend: network (resolved \(host):\(port))"
            case let .failed(message):
                "Backend: network (unavailable: \(message))"
            case .denied:
                "Backend: network (denied: Local Network)"
            }
        case .localRule:
            "Backend: local rule"
        case .tickRangeReplay:
            "Backend: tick-range replay"
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
                NetworkBonjourHTTPImprovBackend(discoveryService: backendDiscoveryService),
                LocalRuleImprovBackend(),
                TickRangeReplayImprovBackend(),
            ]
        )
    }
}
