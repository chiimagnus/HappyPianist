import Foundation
import MIDI

public struct RecordingTakeEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let time: TimeInterval
    public let kind: Kind
    public let observation: PerformanceObservation?

    public enum Kind: Codable, Equatable, Sendable {
        case noteOn(midi: Int, velocity: Int)
        case noteOff(midi: Int)
        case controlChange(controller: Int, value: Int)
        case pitchBend(value: Int)
        case programChange(program: Int)
        case channelPressure(value: Int)
        case polyPressure(midi: Int, value: Int)
    }

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        kind: Kind,
        observation: PerformanceObservation? = nil
    ) {
        self.id = observation?.id ?? id
        self.time = time
        self.kind = kind
        self.observation = observation
    }

    public func validatePrivacy() throws {
        guard let observation else { return }
        try RecordingTakeMetadata.validatePersistenceValue(
            observation.source.id,
            field: "events.observation.source.id"
        )
        try RecordingTakeMetadata.validatePersistenceValue(
            observation.timing.source?.clockID,
            field: "events.observation.timing.source.clockID"
        )
        try RecordingTakeMetadata.validatePersistenceValue(
            observation.timing.mapping?.sourceClockID,
            field: "events.observation.timing.mapping.sourceClockID"
        )
        try RecordingTakeMetadata.validatePersistenceValue(
            observation.calibrationReference,
            field: "events.observation.calibrationReference"
        )
        if case let .contact(id, _, _) = observation.event {
            try RecordingTakeMetadata.validatePersistenceValue(
                id,
                field: "events.observation.contact.id"
            )
        }
    }
}

public struct RecordingInputSourceDescriptor: Codable, Equatable, Sendable {
    public let kind: PerformanceObservation.Source.Kind?
    public let id: String
    public let capabilities: PerformanceInputCapabilities

    public init(
        kind: PerformanceObservation.Source.Kind?,
        id: String,
        capabilities: PerformanceInputCapabilities
    ) {
        self.kind = kind
        self.id = id
        self.capabilities = capabilities
    }
}

public struct RecordingTakeMetadata: Codable, Equatable, Sendable {
    public enum Provenance: String, Codable, Sendable {
        case recorded
    }

    public let provenance: Provenance
    public let scoreIdentity: ScorePerformanceSourceIdentity?
    public let inputSources: [RecordingInputSourceDescriptor]
    public let clockMapping: PerformanceClockMapping?
    public let latencyCorrectionSeconds: TimeInterval?
    public let calibrationVersion: String?

    public init(
        provenance: Provenance = .recorded,
        scoreIdentity: ScorePerformanceSourceIdentity? = nil,
        inputSources: [RecordingInputSourceDescriptor],
        clockMapping: PerformanceClockMapping? = nil,
        latencyCorrectionSeconds: TimeInterval? = nil,
        calibrationVersion: String? = nil
    ) {
        self.provenance = provenance
        self.scoreIdentity = scoreIdentity
        self.inputSources = inputSources
        self.clockMapping = clockMapping
        self.latencyCorrectionSeconds = latencyCorrectionSeconds.flatMap { value in
            value.isFinite ? max(0, value) : nil
        }
        self.calibrationVersion = calibrationVersion
    }

    public static let unattributed = Self(
        inputSources: [RecordingInputSourceDescriptor(
            kind: nil,
            id: "unattributed-recording",
            capabilities: .unavailable
        )]
    )

    public func validatePrivacy() throws {
        try Self.validatePersistenceValue(scoreIdentity?.scoreRevision, field: "scoreIdentity.scoreRevision")
        try Self.validatePersistenceValue(scoreIdentity?.logicalInstrumentID, field: "scoreIdentity.logicalInstrumentID")
        for source in inputSources {
            try Self.validatePersistenceValue(source.id, field: "inputSources.id")
        }
        try Self.validatePersistenceValue(clockMapping?.sourceClockID, field: "clockMapping.sourceClockID")
        try Self.validatePersistenceValue(calibrationVersion, field: "calibrationVersion")
    }

    static func validatePersistenceValue(_ value: String?, field: String) throws {
        guard let value else { return }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.utf8.count <= 256,
              normalized.isEmpty == false,
              normalized.hasPrefix("/") == false,
              normalized.hasPrefix("~") == false,
              normalized.hasPrefix("file:") == false,
              normalized.contains(":/") == false,
              value.contains("\\") == false,
              value.contains("<") == false,
              value.contains(">") == false,
              value.contains("\n") == false,
              value.contains("\r") == false
        else {
            throw RecordingTakeCodingError.unsafeMetadata(field: field)
        }
    }
}

public enum RecordingTakeCodingError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsafeMetadata(field: String)
}

public struct RecordingTake: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public let metadata: RecordingTakeMetadata
    public let events: [RecordingTakeEvent]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        metadata: RecordingTakeMetadata = .unattributed,
        events: [RecordingTakeEvent]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.metadata = metadata
        self.events = events
    }

    public var durationSeconds: TimeInterval {
        events.map(\.time).max() ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case createdAt
        case metadata
        case events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard sourceVersion == Self.currentSchemaVersion else {
            throw RecordingTakeCodingError.unsupportedSchemaVersion(sourceVersion)
        }

        schemaVersion = Self.currentSchemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let decodedMetadata = try container.decode(RecordingTakeMetadata.self, forKey: .metadata)
        metadata = RecordingTakeMetadata(
            provenance: decodedMetadata.provenance,
            scoreIdentity: decodedMetadata.scoreIdentity,
            inputSources: decodedMetadata.inputSources,
            clockMapping: decodedMetadata.clockMapping,
            latencyCorrectionSeconds: decodedMetadata.latencyCorrectionSeconds,
            calibrationVersion: decodedMetadata.calibrationVersion
        )
        events = try container.decode([RecordingTakeEvent].self, forKey: .events)
        try RecordingTakeMetadata.validatePersistenceValue(name, field: "name")
        try metadata.validatePrivacy()
        for event in events {
            try event.validatePrivacy()
        }
    }

    public func encode(to encoder: Encoder) throws {
        try metadata.validatePrivacy()
        try RecordingTakeMetadata.validatePersistenceValue(name, field: "name")
        for event in events {
            try event.validatePrivacy()
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(events, forKey: .events)
    }
}
