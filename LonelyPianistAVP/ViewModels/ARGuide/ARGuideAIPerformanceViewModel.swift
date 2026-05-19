import Foundation
import Observation
import os

@MainActor
@Observable
final class ARGuideAIPerformanceViewModel {
    let backendDiscoveryService: BonjourBackendDiscoveryService

    var isVirtualPerformerEnabled = false
    var isAIPerformanceActive = false
    var latestAIPerformanceSchedule: [PracticeSequencerMIDIEvent] = []
    var lastImprovStatusText: String?

    @ObservationIgnored
    private lazy var aiPerformanceCoordinator: AIPerformanceCoordinator = AIPerformanceCoordinator(
        logger: Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
            category: "AIPerformanceCoordinator"
        ),
        backendDiscoveryService: backendDiscoveryService,
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
        switch backendDiscoveryService.state {
            case .idle:
                "Backend: idle"
            case .discovering:
                "Backend: discovering"
            case let .resolved(host, port):
                "Backend: resolved \(host):\(port)"
            case let .failed(message):
                "Backend: unavailable (\(message))"
            case .denied:
                "Backend: denied (Local Network)"
        }
    }

    func updatePracticeSession(_ practiceSessionViewModel: PracticeSessionViewModel) {
        aiPerformanceCoordinator.updatePracticeSession(practiceSessionViewModel)
    }

    func setVirtualPerformerEnabled(_ isEnabled: Bool, practiceSessionViewModel: PracticeSessionViewModel) {
        isVirtualPerformerEnabled = isEnabled
        aiPerformanceCoordinator.updatePracticeSession(practiceSessionViewModel)
        aiPerformanceCoordinator.setEnabled(isEnabled)
    }

    func recordMIDI1EventForPhraseRecordingIfNeeded(_ event: MIDI1InputEvent) {
        aiPerformanceCoordinator.recordMIDI1EventForPhraseRecordingIfNeeded(event)
    }

    func recordMIDI2EventForPhraseRecordingIfNeeded(_ event: MIDI2InputEvent) {
        aiPerformanceCoordinator.recordMIDI2EventForPhraseRecordingIfNeeded(event)
    }

    func recordKeyContactForPhraseRecordingIfNeeded(
        usesBluetoothMIDIInput: Bool,
        keyContact: KeyContactResult,
        nowUptimeSeconds: TimeInterval
    ) {
        aiPerformanceCoordinator.recordKeyContactForPhraseRecordingIfNeeded(
            usesBluetoothMIDIInput: usesBluetoothMIDIInput,
            keyContact: keyContact,
            nowUptimeSeconds: nowUptimeSeconds
        )
    }

    func shutdown() {
        aiPerformanceCoordinator.shutdown()
    }
}
