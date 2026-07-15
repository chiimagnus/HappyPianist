import Foundation

struct PracticeSongIdentity: Codable, Equatable, Hashable, Sendable {
    let songID: UUID
    let scoreRevision: String

    init(songID: UUID, scoreRevision: String) {
        self.songID = songID
        self.scoreRevision = scoreRevision
    }
}

struct PracticeLocalDay: Codable, Equatable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let timeZoneIdentifier: String

    init?(year: Int, month: Int, day: Int, timeZoneIdentifier: String) {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        guard validated.year == year, validated.month == month, validated.day == day else {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
        case timeZoneIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        let timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        guard let localDay = Self(
            year: year,
            month: month,
            day: day,
            timeZoneIdentifier: timeZoneIdentifier
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: container,
                debugDescription: "PracticeLocalDay must be a valid Gregorian date and time zone"
            )
        }
        self = localDay
    }
}

enum PracticeSessionTermination: String, Codable, Equatable, Sendable {
    case open
    case normal
    case recoveredAfterInterruption
}

struct PracticeSessionRecord: Codable, Equatable, Sendable {
    let id: UUID
    let songID: UUID
    let scoreRevision: String
    let windowOpenedAt: Date
    let practiceStartedAt: Date
    let practiceDay: PracticeLocalDay
    let endedAt: Date?
    let lastPersistedAt: Date
    let practiceWindowDurationMilliseconds: Int64
    let activePracticeDurationMilliseconds: Int64
    let termination: PracticeSessionTermination

    init?(
        id: UUID,
        songID: UUID,
        scoreRevision: String,
        windowOpenedAt: Date,
        practiceStartedAt: Date,
        practiceDay: PracticeLocalDay,
        endedAt: Date?,
        lastPersistedAt: Date,
        practiceWindowDurationMilliseconds: Int64,
        activePracticeDurationMilliseconds: Int64,
        termination: PracticeSessionTermination
    ) {
        guard (termination == .open) == (endedAt == nil) else {
            return nil
        }
        self.id = id
        self.songID = songID
        self.scoreRevision = scoreRevision
        self.windowOpenedAt = windowOpenedAt
        self.practiceStartedAt = practiceStartedAt
        self.practiceDay = practiceDay
        self.endedAt = endedAt
        self.lastPersistedAt = lastPersistedAt
        self.practiceWindowDurationMilliseconds = max(0, practiceWindowDurationMilliseconds)
        self.activePracticeDurationMilliseconds = max(0, activePracticeDurationMilliseconds)
        self.termination = termination
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case songID
        case scoreRevision
        case windowOpenedAt
        case practiceStartedAt
        case practiceDay
        case endedAt
        case lastPersistedAt
        case practiceWindowDurationMilliseconds
        case activePracticeDurationMilliseconds
        case termination
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let termination = try container.decode(PracticeSessionTermination.self, forKey: .termination)
        guard let record = Self(
            id: try container.decode(UUID.self, forKey: .id),
            songID: try container.decode(UUID.self, forKey: .songID),
            scoreRevision: try container.decode(String.self, forKey: .scoreRevision),
            windowOpenedAt: try container.decode(Date.self, forKey: .windowOpenedAt),
            practiceStartedAt: try container.decode(Date.self, forKey: .practiceStartedAt),
            practiceDay: try container.decode(PracticeLocalDay.self, forKey: .practiceDay),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            lastPersistedAt: try container.decode(Date.self, forKey: .lastPersistedAt),
            practiceWindowDurationMilliseconds: try container.decode(
                Int64.self,
                forKey: .practiceWindowDurationMilliseconds
            ),
            activePracticeDurationMilliseconds: try container.decode(
                Int64.self,
                forKey: .activePracticeDurationMilliseconds
            ),
            termination: termination
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .termination,
                in: container,
                debugDescription: "Open sessions must not have endedAt; terminated sessions must have endedAt"
            )
        }
        self = record
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
            handMode: try container.decode(PracticeHandMode.self, forKey: .handMode),
            tempoScale: try container.decode(Double.self, forKey: .tempoScale),
            loopEnabled: try container.decode(Bool.self, forKey: .loopEnabled),
            requiredSuccesses: try container.decode(Int.self, forKey: .requiredSuccesses)
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

    private enum CodingKeys: String, CodingKey {
        case songID
        case scoreFileVersionID
        case scoreRevision
        case totalSourceMeasureCount
        case preparedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            songID: try container.decode(UUID.self, forKey: .songID),
            scoreFileVersionID: try container.decodeIfPresent(
                UUID.self,
                forKey: .scoreFileVersionID
            ),
            scoreRevision: try container.decode(String.self, forKey: .scoreRevision),
            totalSourceMeasureCount: try container.decode(
                Int.self,
                forKey: .totalSourceMeasureCount
            ),
            preparedAt: try container.decode(Date.self, forKey: .preparedAt)
        )
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
    case unavailable(description: String)
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
    var sessions: [PracticeSessionRecord]

    init(
        songs: [SongPracticeProgress] = [],
        scoreMetadata: [SongScorePracticeMetadata] = [],
        sessions: [PracticeSessionRecord] = []
    ) {
        self.songs = songs
        self.scoreMetadata = scoreMetadata
        self.sessions = sessions
    }
}
