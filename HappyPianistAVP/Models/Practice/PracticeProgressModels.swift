import Foundation

struct PracticeSongIdentity: Codable, Equatable, Hashable, Sendable {
    let songID: UUID
    let scoreRevision: String

    init(songID: UUID, scoreRevision: String) {
        self.songID = songID
        self.scoreRevision = scoreRevision
    }
}

struct PracticeSourceMeasureID: Codable, Equatable, Hashable, Sendable {
    let partID: String
    let sourceMeasureIndex: Int
    let sourceNumberToken: String?

    init(partID: String, sourceMeasureIndex: Int, sourceNumberToken: String? = nil) {
        self.partID = partID
        self.sourceMeasureIndex = max(0, sourceMeasureIndex)
        self.sourceNumberToken = sourceNumberToken
    }
}

struct PracticeMeasureOccurrenceID: Codable, Equatable, Hashable, Sendable {
    let sourceMeasureID: PracticeSourceMeasureID
    let occurrenceIndex: Int

    init(sourceMeasureID: PracticeSourceMeasureID, occurrenceIndex: Int) {
        self.sourceMeasureID = sourceMeasureID
        self.occurrenceIndex = max(0, occurrenceIndex)
    }
}

struct PracticePassage: Codable, Equatable, Sendable {
    let start: PracticeMeasureOccurrenceID
    let end: PracticeMeasureOccurrenceID

    init?(start: PracticeMeasureOccurrenceID, end: PracticeMeasureOccurrenceID) {
        guard start.sourceMeasureID.partID == end.sourceMeasureID.partID,
              start.occurrenceIndex <= end.occurrenceIndex
        else {
            return nil
        }
        self.start = start
        self.end = end
    }
}

struct PracticeRoundConfiguration: Codable, Equatable, Sendable {
    static let supportedTempoRange = 0.5 ... 1.0
    static let supportedSuccessRange = 1 ... 5

    let passage: PracticePassage
    let handMode: PracticeHandMode
    let tempoScale: Double
    let loopEnabled: Bool
    let requiredSuccesses: Int

    init(
        passage: PracticePassage,
        handMode: PracticeHandMode,
        tempoScale: Double,
        loopEnabled: Bool,
        requiredSuccesses: Int
    ) {
        self.passage = passage
        self.handMode = handMode
        self.tempoScale = min(max(tempoScale, Self.supportedTempoRange.lowerBound), Self.supportedTempoRange.upperBound)
        self.loopEnabled = loopEnabled
        self.requiredSuccesses = min(
            max(requiredSuccesses, Self.supportedSuccessRange.lowerBound),
            Self.supportedSuccessRange.upperBound
        )
    }

    private enum CodingKeys: String, CodingKey {
        case passage
        case handMode
        case tempoScale
        case loopEnabled
        case requiredSuccesses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            passage: try container.decode(PracticePassage.self, forKey: .passage),
            handMode: try container.decodeIfPresent(PracticeHandMode.self, forKey: .handMode) ?? .both,
            tempoScale: try container.decodeIfPresent(Double.self, forKey: .tempoScale) ?? 1,
            loopEnabled: try container.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false,
            requiredSuccesses: try container.decodeIfPresent(Int.self, forKey: .requiredSuccesses) ?? 3
        )
    }
}

struct PracticeResumePoint: Codable, Equatable, Sendable {
    let occurrenceID: PracticeMeasureOccurrenceID
    let stepIndex: Int
    let updatedAt: Date

    init(occurrenceID: PracticeMeasureOccurrenceID, stepIndex: Int, updatedAt: Date) {
        self.occurrenceID = occurrenceID
        self.stepIndex = max(0, stepIndex)
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case occurrenceID
        case stepIndex
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            occurrenceID: try container.decode(PracticeMeasureOccurrenceID.self, forKey: .occurrenceID),
            stepIndex: try container.decodeIfPresent(Int.self, forKey: .stepIndex) ?? 0,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        )
    }
}

enum MeasureLearningState: String, Codable, Equatable, Sendable {
    case notStarted
    case learning
    case stable
}

enum PracticeIssueKind: String, Codable, Equatable, Sendable {
    case wrongNote
    case missedNote
    case incompleteChord
}

struct MeasurePracticeFacts: Codable, Equatable, Sendable {
    let sourceMeasureID: PracticeSourceMeasureID
    let handMode: PracticeHandMode
    var state: MeasureLearningState
    var successfulAttempts: Int
    var failedAttempts: Int
    var consecutiveSuccesses: Int
    var highestStableTempoScale: Double?
    var recentIssue: PracticeIssueKind?
    var lastAttemptAt: Date?

    init(
        sourceMeasureID: PracticeSourceMeasureID,
        handMode: PracticeHandMode,
        state: MeasureLearningState = .notStarted,
        successfulAttempts: Int = 0,
        failedAttempts: Int = 0,
        consecutiveSuccesses: Int = 0,
        highestStableTempoScale: Double? = nil,
        recentIssue: PracticeIssueKind? = nil,
        lastAttemptAt: Date? = nil
    ) {
        self.sourceMeasureID = sourceMeasureID
        self.handMode = handMode
        self.state = state
        self.successfulAttempts = max(0, successfulAttempts)
        self.failedAttempts = max(0, failedAttempts)
        self.consecutiveSuccesses = max(0, consecutiveSuccesses)
        self.highestStableTempoScale = highestStableTempoScale.map {
            min(max($0, PracticeRoundConfiguration.supportedTempoRange.lowerBound), PracticeRoundConfiguration.supportedTempoRange.upperBound)
        }
        self.recentIssue = recentIssue
        self.lastAttemptAt = lastAttemptAt
    }

    private enum CodingKeys: String, CodingKey {
        case sourceMeasureID
        case handMode
        case state
        case successfulAttempts
        case failedAttempts
        case consecutiveSuccesses
        case highestStableTempoScale
        case recentIssue
        case lastAttemptAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sourceMeasureID: try container.decode(PracticeSourceMeasureID.self, forKey: .sourceMeasureID),
            handMode: try container.decodeIfPresent(PracticeHandMode.self, forKey: .handMode) ?? .both,
            state: try container.decodeIfPresent(MeasureLearningState.self, forKey: .state) ?? .notStarted,
            successfulAttempts: try container.decodeIfPresent(Int.self, forKey: .successfulAttempts) ?? 0,
            failedAttempts: try container.decodeIfPresent(Int.self, forKey: .failedAttempts) ?? 0,
            consecutiveSuccesses: try container.decodeIfPresent(Int.self, forKey: .consecutiveSuccesses) ?? 0,
            highestStableTempoScale: try container.decodeIfPresent(Double.self, forKey: .highestStableTempoScale),
            recentIssue: try container.decodeIfPresent(PracticeIssueKind.self, forKey: .recentIssue),
            lastAttemptAt: try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        )
    }
}

struct SongPracticeProgress: Codable, Equatable, Sendable {
    let identity: PracticeSongIdentity
    var activeConfiguration: PracticeRoundConfiguration?
    var resumePoint: PracticeResumePoint?
    var measureFacts: [MeasurePracticeFacts]
    var updatedAt: Date

    init(
        identity: PracticeSongIdentity,
        activeConfiguration: PracticeRoundConfiguration? = nil,
        resumePoint: PracticeResumePoint? = nil,
        measureFacts: [MeasurePracticeFacts] = [],
        updatedAt: Date
    ) {
        self.identity = identity
        self.activeConfiguration = activeConfiguration
        self.resumePoint = resumePoint
        self.measureFacts = measureFacts
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case activeConfiguration
        case resumePoint
        case measureFacts
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            identity: try container.decode(PracticeSongIdentity.self, forKey: .identity),
            activeConfiguration: try container.decodeIfPresent(PracticeRoundConfiguration.self, forKey: .activeConfiguration),
            resumePoint: try container.decodeIfPresent(PracticeResumePoint.self, forKey: .resumePoint),
            measureFacts: try container.decodeIfPresent([MeasurePracticeFacts].self, forKey: .measureFacts) ?? [],
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        )
    }
}

struct PracticeProgressDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var songs: [SongPracticeProgress]

    init(schemaVersion: Int = Self.currentSchemaVersion, songs: [SongPracticeProgress] = []) {
        self.schemaVersion = schemaVersion
        self.songs = songs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case songs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        songs = try container.decodeIfPresent([SongPracticeProgress].self, forKey: .songs) ?? []
    }
}
