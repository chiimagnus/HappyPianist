import Diagnostics
import Foundation

enum PianoPerformanceAudioOperation: String, Codable, CaseIterable {
    case audioSessionConfiguration
    case soundFontLoad
    case engineStart
    case sequenceLoad
    case sequenceStart
    case commandRender
    case interruption
    case routeChange
    case mediaServicesReset
    case transportReset
}

enum PianoPerformanceAudioRecovery: String, Codable, CaseIterable {
    case recoverable
    case unrecoverable
}

enum PianoPerformanceAudioLifecycleReason: String, Codable, CaseIterable {
    case operationError
    case interruptionDefault
    case interruptionAppSuspended
    case interruptionBuiltInMicMuted
    case interruptionRouteDisconnected
    case interruptionSceneBackgrounded
    case interruptionUnknown
    case routeUnknown
    case routeNewDeviceAvailable
    case routeOldDeviceUnavailable
    case routeCategoryChange
    case routeOverride
    case routeWakeFromSleep
    case routeNoSuitableRoute
    case routeConfigurationChange
    case mediaServicesReset
}

enum PianoPerformanceAudioResetOutcome: String, Codable, CaseIterable {
    case succeeded
    case failed
    case notRequired
}

struct PianoPerformanceAudioDiagnosticSample: Equatable {
    let outcome: PianoPerformanceDiagnosticOutcome
    let operation: PianoPerformanceAudioOperation
    let recovery: PianoPerformanceAudioRecovery
    let reason: PianoPerformanceAudioLifecycleReason
    let resetOutcome: PianoPerformanceAudioResetOutcome

    var diagnosticEvent: DiagnosticEvent {
        DiagnosticEvent(
            severity: outcome == .succeeded ? .info : .error,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.playback.rawValue,
            summary: "本地音源恢复状态",
            reason: [
                "outcome=\(outcome.rawValue)",
                "capability=\(PianoPerformanceDiagnosticCapability.localSampler.rawValue)",
                "operation=\(operation.rawValue)",
                "recovery=\(recovery.rawValue)",
                "reason=\(reason.rawValue)",
                "reset=\(resetOutcome.rawValue)",
            ].joined(separator: ";"),
            persistence: .systemOnly
        )
    }
}
