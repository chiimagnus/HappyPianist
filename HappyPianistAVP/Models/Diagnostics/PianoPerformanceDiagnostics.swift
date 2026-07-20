import Foundation

enum PianoPerformanceDiagnosticStage: String, Codable, CaseIterable, Sendable {
    case preparation
    case plan
    case playback
    case input
    case alignment
    case assessment
}

enum PianoPerformanceDiagnosticOutcome: String, Codable, CaseIterable, Sendable {
    case started
    case succeeded
    case failed
    case unsupported
    case mismatch
}

enum PianoPerformanceDiagnosticCapability: String, Codable, CaseIterable, Sendable {
    case scoreParsing
    case performancePlan
    case localSampler
    case externalMIDI
    case midiInput
    case audioPitchInput
    case handTrackingInput
    case scoreAlignment
    case performanceAssessment
}

enum PianoPerformanceAudioOperation: String, Codable, CaseIterable, Sendable {
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

enum PianoPerformanceAudioRecovery: String, Codable, CaseIterable, Sendable {
    case recoverable
    case unrecoverable
}

enum PianoPerformanceAudioLifecycleReason: String, Codable, CaseIterable, Sendable {
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

enum PianoPerformanceAudioResetOutcome: String, Codable, CaseIterable, Sendable {
    case succeeded
    case failed
    case notRequired
}

struct PianoPerformanceAudioDiagnosticSample: Equatable, Sendable {
    let outcome: PianoPerformanceDiagnosticOutcome
    let operation: PianoPerformanceAudioOperation
    let recovery: PianoPerformanceAudioRecovery
    let reason: PianoPerformanceAudioLifecycleReason
    let resetOutcome: PianoPerformanceAudioResetOutcome

    var diagnosticEvent: DiagnosticEvent {
        let fields = [
            "outcome=\(outcome.rawValue)",
            "capability=\(PianoPerformanceDiagnosticCapability.localSampler.rawValue)",
            "operation=\(operation.rawValue)",
            "recovery=\(recovery.rawValue)",
            "reason=\(reason.rawValue)",
            "reset=\(resetOutcome.rawValue)",
        ]
        return DiagnosticEvent(
            severity: outcome == .succeeded ? .info : .error,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.playback.rawValue,
            summary: "本地音源恢复状态",
            reason: fields.joined(separator: ";"),
            persistence: .systemOnly
        )
    }
}

enum PianoPerformanceDurationBucket: String, Codable, CaseIterable, Sendable {
    case underTenMilliseconds
    case underFiftyMilliseconds
    case underTwoHundredMilliseconds
    case underOneSecond
    case oneSecondOrMore

    init(seconds: TimeInterval) {
        switch max(0, seconds) {
        case ..<0.01:
            self = .underTenMilliseconds
        case ..<0.05:
            self = .underFiftyMilliseconds
        case ..<0.2:
            self = .underTwoHundredMilliseconds
        case ..<1:
            self = .underOneSecond
        default:
            self = .oneSecondOrMore
        }
    }

    init(duration: Duration) {
        let components = duration.components
        self.init(
            seconds: TimeInterval(components.seconds) +
                TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}

struct PianoPerformanceDiagnosticSample: Equatable, Sendable {
    let stage: PianoPerformanceDiagnosticStage
    let outcome: PianoPerformanceDiagnosticOutcome
    let capability: PianoPerformanceDiagnosticCapability
    let itemCount: Int
    let durationBucket: PianoPerformanceDurationBucket?
    let persistence: DiagnosticPersistence

    init(
        stage: PianoPerformanceDiagnosticStage,
        outcome: PianoPerformanceDiagnosticOutcome,
        capability: PianoPerformanceDiagnosticCapability,
        itemCount: Int = 0,
        durationBucket: PianoPerformanceDurationBucket? = nil,
        exportable: Bool = false
    ) {
        self.stage = stage
        self.outcome = outcome
        self.capability = capability
        self.itemCount = max(0, itemCount)
        self.durationBucket = durationBucket
        persistence = exportable ? .exportable : .systemOnly
    }

    var diagnosticEvent: DiagnosticEvent {
        let fields = [
            "outcome=\(outcome.rawValue)",
            "capability=\(capability.rawValue)",
            "count=\(itemCount)",
            "duration=\(durationBucket?.rawValue ?? "none")",
        ]
        return DiagnosticEvent(
            severity: severity,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: stage.rawValue,
            summary: "钢琴演奏链路事件",
            reason: fields.joined(separator: ";"),
            persistence: persistence
        )
    }

    private var severity: DiagnosticSeverity {
        switch outcome {
        case .started, .succeeded:
            .info
        case .unsupported, .mismatch:
            .warning
        case .failed:
            .error
        }
    }
}

struct PianoPerformancePlanBuildDiagnosticSample: Equatable, Sendable {
    let songID: UUID
    let scoreRevision: String
    let durationBucket: PianoPerformanceDurationBucket
    let noteEventCount: Int
    let tempoEventCount: Int
    let controllerEventCount: Int
    let annotationCount: Int
    let unsupportedNoteCount: Int
    let approximationCount: Int
    let stepMismatchCount: Int
    let highlightMismatchCount: Int
    let notationMismatchCount: Int

    var diagnosticEvent: DiagnosticEvent {
        let fields = [
            "outcome=\(outcome.rawValue)",
            "duration=\(durationBucket.rawValue)",
            "noteEvents=\(max(0, noteEventCount))",
            "tempoEvents=\(max(0, tempoEventCount))",
            "controllerEvents=\(max(0, controllerEventCount))",
            "annotations=\(max(0, annotationCount))",
            "unsupportedNotes=\(max(0, unsupportedNoteCount))",
            "approximations=\(max(0, approximationCount))",
            "stepMismatches=\(max(0, stepMismatchCount))",
            "highlightMismatches=\(max(0, highlightMismatchCount))",
            "notationMismatches=\(max(0, notationMismatchCount))",
        ]
        return DiagnosticEvent(
            severity: outcome == .succeeded ? .info : .warning,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.plan.rawValue,
            summary: "钢琴演奏计划构建结果",
            reason: fields.joined(separator: ";"),
            songID: songID,
            scoreRevision: scoreRevision,
            persistence: .systemOnly
        )
    }

    private var outcome: PianoPerformanceDiagnosticOutcome {
        if stepMismatchCount > 0 || highlightMismatchCount > 0 || notationMismatchCount > 0 {
            return .mismatch
        }
        if unsupportedNoteCount > 0 {
            return .unsupported
        }
        return .succeeded
    }
}

struct PianoPerformanceNotationFallbackDiagnosticSample: Equatable, Sendable {
    private struct Key: Hashable {
        let kind: ScoreNotationProjection.Fallback.Kind
        let sourceKindToken: String?
        let reason: ScoreNotationProjection.Fallback.Reason
    }

    let kind: ScoreNotationProjection.Fallback.Kind
    let sourceKindToken: String?
    let reason: ScoreNotationProjection.Fallback.Reason
    let count: Int

    static func aggregated(
        from fallbacks: [ScoreNotationProjection.Fallback]
    ) -> [PianoPerformanceNotationFallbackDiagnosticSample] {
        Dictionary(grouping: fallbacks) { fallback in
            Key(kind: fallback.kind, sourceKindToken: fallback.sourceKindToken, reason: fallback.reason)
        }.map { key, fallbacks in
            PianoPerformanceNotationFallbackDiagnosticSample(
                kind: key.kind,
                sourceKindToken: key.sourceKindToken,
                reason: key.reason,
                count: fallbacks.count
            )
        }.sorted {
            if $0.kind.rawValue != $1.kind.rawValue { return $0.kind.rawValue < $1.kind.rawValue }
            if ($0.sourceKindToken ?? "") != ($1.sourceKindToken ?? "") {
                return ($0.sourceKindToken ?? "") < ($1.sourceKindToken ?? "")
            }
            return $0.reason.rawValue < $1.reason.rawValue
        }
    }

    var diagnosticEvent: DiagnosticEvent {
        DiagnosticEvent(
            severity: .warning,
            code: .pianoPerformancePipeline,
            category: .pianoPerformance,
            stage: PianoPerformanceDiagnosticStage.plan.rawValue,
            summary: "记谱降级聚合",
            reason: [
                "kind=\(kind.rawValue)",
                "count=\(max(0, count))",
                "reason=\(reason.rawValue)",
                "sourceKind=\(sourceKindToken ?? "unspecified")",
            ].joined(separator: ";"),
            persistence: .systemOnly
        )
    }
}
