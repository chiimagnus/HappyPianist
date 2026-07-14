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
}

struct SongScorePracticeMetadata: Codable, Equatable, Sendable {
    let songID: UUID
    let scoreFileVersionID: UUID?
    let scoreRevision: String
    let totalSourceMeasureCount: Int
    let preparedAt: Date

    init(
        songID: UUID,
        scoreFileVersionID: UUID?,
        scoreRevision: String,
        totalSourceMeasureCount: Int,
        preparedAt: Date
    ) {
        self.songID = songID
        self.scoreFileVersionID = scoreFileVersionID
        self.scoreRevision = scoreRevision
        self.totalSourceMeasureCount = max(0, totalSourceMeasureCount)
        self.preparedAt = preparedAt
    }
}

enum SongScorePracticeMetadataOrder {
    static func preferred(
        _ lhs: SongScorePracticeMetadata,
        over rhs: SongScorePracticeMetadata
    ) -> Bool {
        if lhs.preparedAt != rhs.preparedAt { return lhs.preparedAt > rhs.preparedAt }
        if lhs.scoreRevision != rhs.scoreRevision { return lhs.scoreRevision > rhs.scoreRevision }
        if lhs.totalSourceMeasureCount != rhs.totalSourceMeasureCount {
            return lhs.totalSourceMeasureCount > rhs.totalSourceMeasureCount
        }
        return canonicalKey(lhs) > canonicalKey(rhs)
    }

    static func preferred(
        in metadata: [SongScorePracticeMetadata]
    ) -> SongScorePracticeMetadata? {
        metadata.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return preferred(candidate, over: current) ? candidate : current
        }
    }

    private static func canonicalKey(_ metadata: SongScorePracticeMetadata) -> String {
        "\(metadata.songID.uuidString)|\(metadata.scoreFileVersionID?.uuidString ?? "<nil>")|\(metadata.scoreRevision)"
    }
}

struct PracticeSongHistory: Equatable, Sendable {
    let songID: UUID
    let progresses: [SongPracticeProgress]
    let scoreMetadata: [SongScorePracticeMetadata]
}

enum PracticeSongHistoryLoadResult: Equatable, Sendable {
    case loaded(PracticeSongHistory)
    case corrupted(description: String)
}

enum PracticeProgressRecordOrder {
    static func preferred(
        _ lhs: SongPracticeProgress,
        over rhs: SongPracticeProgress
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        let lhsData = canonicalData(lhs)
        let rhsData = canonicalData(rhs)
        return lhsData != rhsData && rhsData.lexicographicallyPrecedes(lhsData)
    }

    static func preferred(in progresses: [SongPracticeProgress]) -> SongPracticeProgress? {
        progresses.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return preferred(candidate, over: current) ? candidate : current
        }
    }

    static func sorted(_ progresses: [SongPracticeProgress]) -> [SongPracticeProgress] {
        progresses.sorted { lhs, rhs in
            if lhs.identity.songID != rhs.identity.songID {
                return lhs.identity.songID.uuidString < rhs.identity.songID.uuidString
            }
            if lhs.identity.scoreRevision != rhs.identity.scoreRevision {
                return lhs.identity.scoreRevision < rhs.identity.scoreRevision
            }
            return preferred(lhs, over: rhs)
        }
    }

    private static func canonicalData(_ progress: SongPracticeProgress) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(progress)) ?? Data()
    }
}

struct PracticeProgressDocument: Codable, Equatable, Sendable {
    var songs: [SongPracticeProgress]
    var scoreMetadata: [SongScorePracticeMetadata]

    init(
        songs: [SongPracticeProgress] = [],
        scoreMetadata: [SongScorePracticeMetadata] = []
    ) {
        self.songs = songs
        self.scoreMetadata = scoreMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case songs
        case scoreMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songs = try container.decodeIfPresent([SongPracticeProgress].self, forKey: .songs) ?? []
        scoreMetadata = try container.decodeIfPresent([SongScorePracticeMetadata].self, forKey: .scoreMetadata) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(songs, forKey: .songs)
        try container.encode(scoreMetadata, forKey: .scoreMetadata)
    }
}
