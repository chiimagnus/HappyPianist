import Foundation

struct RecordingTakeEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let time: TimeInterval
    let kind: Kind
    let observation: PerformanceObservation?

    enum Kind: Codable, Equatable, Sendable {
        case noteOn(midi: Int, velocity: Int)
        case noteOff(midi: Int)
        case controlChange(controller: Int, value: Int)
        case pitchBend(value: Int)
        case programChange(program: Int)
        case channelPressure(value: Int)
        case polyPressure(midi: Int, value: Int)
    }

    init(
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

    func validatePrivacy() throws {
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

struct RecordingInputSourceDescriptor: Codable, Equatable, Sendable {
    let kind: PerformanceObservation.Source.Kind?
    let id: String
    let capabilities: PerformanceInputCapabilities
}

struct RecordingTakeMetadata: Codable, Equatable, Sendable {
    enum Provenance: String, Codable, Sendable {
        case recorded
        case legacy
    }

    let provenance: Provenance
    let scoreIdentity: ScorePerformanceSourceIdentity?
    let inputSources: [RecordingInputSourceDescriptor]
    let clockMapping: PerformanceClockMapping?
    let latencyCorrectionSeconds: TimeInterval?
    let calibrationVersion: String?

    init(
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

    static let unattributed = Self(
        inputSources: [RecordingInputSourceDescriptor(
            kind: nil,
            id: "unattributed-recording",
            capabilities: .recordingUnavailable
        )]
    )

    static let legacy = Self(
        provenance: .legacy,
        inputSources: [RecordingInputSourceDescriptor(
            kind: nil,
            id: "legacy-unattributed",
            capabilities: .recordingUnavailable
        )]
    )

    func validatePrivacy() throws {
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

private extension PerformanceInputCapabilities {
    static let recordingUnavailable = Self(
        pitch: .unavailable,
        onset: .unavailable,
        release: .unavailable,
        velocity: .unavailable,
        controllers: .unavailable,
        polyphony: .unavailable,
        hand: .unavailable,
        finger: .unavailable,
        position: .unavailable,
        confidence: .unavailable
    )
}

enum RecordingTakeCodingError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case unsafeMetadata(field: String)
}

struct RecordingTake: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let id: UUID
    var name: String
    let createdAt: Date
    let metadata: RecordingTakeMetadata
    let events: [RecordingTakeEvent]

    init(
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

    var durationSeconds: TimeInterval {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1 ... Self.currentSchemaVersion).contains(sourceVersion) else {
            throw RecordingTakeCodingError.unsupportedSchemaVersion(sourceVersion)
        }

        schemaVersion = Self.currentSchemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let decodedMetadata = try container.decodeIfPresent(
            RecordingTakeMetadata.self,
            forKey: .metadata
        ) ?? .legacy
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

    func encode(to encoder: Encoder) throws {
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
