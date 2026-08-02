import Foundation

public enum PianoPerformanceDiagnosticStage: String, Codable, CaseIterable, Sendable {
    case preparation
    case plan
    case playback
    case input
    case alignment
    case assessment
    case coaching
}

public enum PianoPerformanceDiagnosticOutcome: String, Codable, CaseIterable, Sendable {
    case started
    case succeeded
    case failed
    case unsupported
    case mismatch
}

public enum PianoPerformanceDiagnosticCapability: String, Codable, CaseIterable, Sendable {
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

public enum PianoPerformanceDurationBucket: String, Codable, CaseIterable, Sendable {
    case underTenMilliseconds
    case underFiftyMilliseconds
    case underTwoHundredMilliseconds
    case underOneSecond
    case oneSecondOrMore

    public init(seconds: TimeInterval) {
        switch max(0, seconds) {
        case ..<0.01: self = .underTenMilliseconds
        case ..<0.05: self = .underFiftyMilliseconds
        case ..<0.2: self = .underTwoHundredMilliseconds
        case ..<1: self = .underOneSecond
        default: self = .oneSecondOrMore
        }
    }

    public init(duration: Duration) {
        let components = duration.components
        self.init(
            seconds: TimeInterval(components.seconds) +
                TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        )
    }
}

public struct PianoPerformanceDiagnosticSample: Equatable, Sendable {
    public let stage: PianoPerformanceDiagnosticStage
    public let outcome: PianoPerformanceDiagnosticOutcome
    public let capability: PianoPerformanceDiagnosticCapability
    public let itemCount: Int
    public let durationBucket: PianoPerformanceDurationBucket?
    public let persistence: DiagnosticPersistence

    public init(
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

    public var diagnosticEvent: DiagnosticEvent {
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
        case .started, .succeeded: .info
        case .unsupported, .mismatch: .warning
        case .failed: .error
        }
    }
}
