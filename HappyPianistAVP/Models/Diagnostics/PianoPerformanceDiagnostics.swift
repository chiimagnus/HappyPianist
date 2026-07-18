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

struct PianoPerformanceDiagnostics: Sendable {
    private let reporter: any DiagnosticsReporting

    init(reporter: any DiagnosticsReporting) {
        self.reporter = reporter
    }

    func recordSystem(_ sample: PianoPerformanceDiagnosticSample) {
        reporter.recordSystem(sample.diagnosticEvent)
    }

    @discardableResult
    func record(_ sample: PianoPerformanceDiagnosticSample) async -> DiagnosticRecordResult {
        await reporter.record(sample.diagnosticEvent)
    }
}
