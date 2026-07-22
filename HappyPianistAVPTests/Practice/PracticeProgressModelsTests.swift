import Foundation
@testable import HappyPianistAVP
import Testing

private func makeOccurrence(_ index: Int, partID: String = "P1") -> PracticeMeasureOccurrenceID {
    PracticeMeasureOccurrenceID(
        sourceMeasureID: PracticeSourceMeasureID(
            partID: partID,
            sourceMeasureIndex: index,
            sourceNumberToken: String(index + 1)
        ),
        occurrenceIndex: index
    )
}

@Test
func practiceProgressDocumentRoundTrips() throws {
    let passage = try #require(PracticePassage(start: makeOccurrence(1), end: makeOccurrence(4)))
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "sha256:abc")
    let date = Date(timeIntervalSince1970: 1234)
    let configuration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .right,
        tempoScale: 0.6,
        loopEnabled: true,
        requiredSuccesses: 3
    )
    let practiceDay = try #require(PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    ))
    let session = try #require(PracticeSessionRecord(
        id: UUID(),
        songID: identity.songID,
        scoreRevision: identity.scoreRevision,
        windowOpenedAt: date,
        practiceStartedAt: date,
        practiceDay: practiceDay,
        endedAt: date,
        lastPersistedAt: date,
        practiceWindowDurationMilliseconds: 4000,
        activePracticeDurationMilliseconds: 2000,
        termination: .normal
    ))
    let document = PracticeProgressDocument(
        songs: [SongPracticeProgress(
            identity: identity,
            activeConfiguration: configuration,
            resumePoint: PracticeResumePoint(occurrenceID: makeOccurrence(2), stepIndex: 7, updatedAt: date),
            measureFacts: [
                MeasurePracticeFacts(
                    sourceMeasureID: makeOccurrence(2).sourceMeasureID,
                    handMode: .right,
                    state: .learning,
                    successfulAttempts: 2,
                    failedAttempts: 1,
                    consecutiveSuccesses: 2,
                    recentIssue: .incompleteChord,
                    lastAttemptAt: date
                ),
            ],
            updatedAt: date
        )],
        sessions: [session]
    )

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(PracticeProgressDocument.self, from: data)

    #expect(decoded == document)
}

@Test
func practiceProgressV2RejectsInconsistentPerformanceMaturityFacts() throws {
    let metric = PerformanceAssessmentDimensionResult(
        dimension: .exactPitch,
        outcome: .correct,
        evidenceStatus: .observed,
        measurement: PerformanceAssessmentMeasurement(value: 1, unit: .ratio),
        sampleCount: 1,
        confidence: 1,
        evidence: []
    )
    let maturity = MeasurePerformanceMaturitySummary(
        maturity: .mature,
        rubricVersion: PerformanceAssessmentRubricVersion.capabilityAware.rawValue,
        assessedDimensionCount: 1,
        sampleCount: 1,
        evidenceCoverage: 1,
        metricSummaries: [MeasurePerformanceMetricSummary(metric)],
        assessedAt: Date(timeIntervalSince1970: 100)
    )
    let document = PracticeProgressDocument(songs: [SongPracticeProgress(
        identity: PracticeSongIdentity(songID: UUID(), scoreRevision: "strict-v2"),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: makeOccurrence(0).sourceMeasureID,
            handMode: .both,
            performanceMaturity: maturity
        )],
        updatedAt: Date(timeIntervalSince1970: 100)
    )])
    let valid = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any]
    )

    for corruption in [
        "missingMetrics",
        "negativeMetricSamples",
        "invalidConfidence",
        "dimensionCountMismatch",
        "sampleCountMismatch",
        "coverageMismatch",
        "duplicateDimension",
        "maturityMismatch",
    ] {
        var root = valid
        var songs = try #require(root["songs"] as? [[String: Any]])
        var facts = try #require(songs[0]["measureFacts"] as? [[String: Any]])
        var summary = try #require(facts[0]["performanceMaturity"] as? [String: Any])
        var metrics = try #require(summary["metricSummaries"] as? [[String: Any]])
        switch corruption {
        case "missingMetrics": summary.removeValue(forKey: "metricSummaries")
        case "negativeMetricSamples": metrics[0]["sampleCount"] = -1
        case "invalidConfidence": metrics[0]["confidence"] = 2
        case "dimensionCountMismatch": summary["assessedDimensionCount"] = 2
        case "sampleCountMismatch": summary["sampleCount"] = 2
        case "coverageMismatch": summary["evidenceCoverage"] = 0
        case "duplicateDimension":
            metrics.append(metrics[0])
            summary["assessedDimensionCount"] = 2
            summary["sampleCount"] = 2
        case "maturityMismatch": summary["maturity"] = "developing"
        default: break
        }
        if corruption != "missingMetrics" {
            summary["metricSummaries"] = metrics
        }
        facts[0]["performanceMaturity"] = summary
        songs[0]["measureFacts"] = facts
        root["songs"] = songs

        #expect(throws: DecodingError.self, "corruption=\(corruption)") {
            try JSONDecoder().decode(
                PracticeProgressDocument.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        }
    }
}

@Test
func practiceProgressDocumentRequiresEveryTopLevelArray() {
    for json in [
        #"{"scoreMetadata":[],"sessions":[]}"#,
        #"{"songs":[],"sessions":[]}"#,
        #"{"songs":[],"scoreMetadata":[]}"#,
        "{}",
    ] {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PracticeProgressDocument.self, from: Data(json.utf8))
        }
    }
}

@Test
func practiceSessionNormalizesNegativeDurations() throws {
    let day = try #require(PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    ))
    let record = try #require(PracticeSessionRecord(
        id: UUID(),
        songID: UUID(),
        scoreRevision: "revision",
        windowOpenedAt: .distantPast,
        practiceStartedAt: .distantPast,
        practiceDay: day,
        endedAt: nil,
        lastPersistedAt: .distantPast,
        practiceWindowDurationMilliseconds: -1,
        activePracticeDurationMilliseconds: -2,
        termination: .open
    ))

    #expect(record.practiceWindowDurationMilliseconds == 0)
    #expect(record.activePracticeDurationMilliseconds == 0)

    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
    )
    object["practiceWindowDurationMilliseconds"] = -10
    object["activePracticeDurationMilliseconds"] = -20
    let decoded = try JSONDecoder().decode(
        PracticeSessionRecord.self,
        from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(decoded == record)
}

@Test
func practiceSessionRejectsTerminationAndEndedAtMismatch() throws {
    let day = try #require(PracticeLocalDay(
        year: 2026,
        month: 7,
        day: 15,
        timeZoneIdentifier: "Asia/Singapore"
    ))
    let date = Date(timeIntervalSince1970: 100)

    #expect(PracticeSessionRecord(
        id: UUID(),
        songID: UUID(),
        scoreRevision: "revision",
        windowOpenedAt: date,
        practiceStartedAt: date,
        practiceDay: day,
        endedAt: date,
        lastPersistedAt: date,
        practiceWindowDurationMilliseconds: 0,
        activePracticeDurationMilliseconds: 0,
        termination: .open
    ) == nil)
    #expect(PracticeSessionRecord(
        id: UUID(),
        songID: UUID(),
        scoreRevision: "revision",
        windowOpenedAt: date,
        practiceStartedAt: date,
        practiceDay: day,
        endedAt: nil,
        lastPersistedAt: date,
        practiceWindowDurationMilliseconds: 0,
        activePracticeDurationMilliseconds: 0,
        termination: .normal
    ) == nil)
}

@Test
func practiceSessionStrictDecodeRejectsInvalidLocalDayAndTermination() throws {
    let valid = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "songID": "00000000-0000-0000-0000-000000000002",
      "scoreRevision": "revision",
      "windowOpenedAt": -978307100,
      "practiceStartedAt": -978307100,
      "practiceDay": {
        "year": 2026,
        "month": 7,
        "day": 15,
        "timeZoneIdentifier": "Asia/Singapore"
      },
      "lastPersistedAt": -978307100,
      "practiceWindowDurationMilliseconds": 0,
      "activePracticeDurationMilliseconds": 0,
      "termination": "normal"
    }
    """
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PracticeSessionRecord.self, from: Data(valid.utf8))
    }

    let invalidDay = valid
        .replacing(#""day": 15"#, with: #""day": 32"#)
        .replacing(#""termination": "normal""#, with: #""termination": "open""#)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PracticeSessionRecord.self, from: Data(invalidDay.utf8))
    }
}

@Test
func scoreMetadataDecodeRejectsMissingFileVersion() {
    let songID = UUID()
    let json = """
    {
      "songs": [],
      "scoreMetadata": [{
        "songID": "\(songID.uuidString)",
        "scoreRevision": "legacy",
        "totalSourceMeasureCount": 0,
        "preparedAt": 10
      }],
      "sessions": []
    }
    """

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(PracticeProgressDocument.self, from: Data(json.utf8))
    }
}

@Test
func scoreMetadataDecodeNormalizesNegativeMeasureTotal() throws {
    let songID = UUID()
    let scoreFileVersionID = UUID()
    let json = """
    {
      "songs": [],
      "scoreMetadata": [{
        "songID": "\(songID.uuidString)",
        "scoreFileVersionID": "\(scoreFileVersionID.uuidString)",
        "scoreRevision": "r1",
        "totalSourceMeasureCount": -3,
        "preparedAt": "1970-01-01T00:00:10Z"
      }],
      "sessions": []
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let document = try decoder.decode(PracticeProgressDocument.self, from: Data(json.utf8))

    #expect(document.scoreMetadata.first?.scoreFileVersionID == scoreFileVersionID)
    #expect(document.scoreMetadata.first?.totalSourceMeasureCount == 0)
}

@Test
func duplicateProgressTieBreakDoesNotDependOnDocumentOrder() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let date = Date(timeIntervalSince1970: 100)
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let first = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            successfulAttempts: 1,
            lastAttemptAt: date
        )],
        updatedAt: date
    )
    let second = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            failedAttempts: 1,
            lastAttemptAt: date
        )],
        updatedAt: date
    )

    #expect(
        PracticeProgressRecordOrder.preferred(in: [first, second])
            == PracticeProgressRecordOrder.preferred(in: [second, first])
    )
}

@Test
func duplicateProgressTieBreakPreservesNestedDateFractions() {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let updatedAt = Date(timeIntervalSince1970: 100)
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0)
    let first = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            failedAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 100.1)
        )],
        updatedAt: updatedAt
    )
    let second = SongPracticeProgress(
        identity: identity,
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: .right,
            failedAttempts: 1,
            lastAttemptAt: Date(timeIntervalSince1970: 100.2)
        )],
        updatedAt: updatedAt
    )

    #expect(
        PracticeProgressRecordOrder.preferred(in: [first, second])
            == PracticeProgressRecordOrder.preferred(in: [second, first])
    )
}

@Test
func roundConfigurationClampsSupportedValues() throws {
    let passage = try #require(PracticePassage(start: makeOccurrence(0), end: makeOccurrence(0)))
    let low = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 0.1,
        loopEnabled: false,
        requiredSuccesses: 0
    )
    let high = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 2,
        loopEnabled: false,
        requiredSuccesses: 99
    )

    #expect(low.tempoScale == 0.5)
    #expect(low.requiredSuccesses == 1)
    #expect(high.tempoScale == 1.0)
    #expect(high.requiredSuccesses == 5)
}

@Test
func roundConfigurationDecodeCannotBypassSupportedRanges() throws {
    let passage = try #require(PracticePassage(start: makeOccurrence(0), end: makeOccurrence(0)))
    let valid = PracticeRoundConfiguration(
        passage: passage,
        handMode: .both,
        tempoScale: 1,
        loopEnabled: false,
        requiredSuccesses: 1
    )
    var object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
    )
    object["tempoScale"] = -1
    object["requiredSuccesses"] = 999

    let decoded = try JSONDecoder().decode(
        PracticeRoundConfiguration.self,
        from: JSONSerialization.data(withJSONObject: object)
    )

    #expect(decoded.tempoScale == PracticeRoundConfiguration.supportedTempoRange.lowerBound)
    #expect(decoded.requiredSuccesses == PracticeRoundConfiguration.supportedSuccessRange.upperBound)
}

@Test
func passageRejectsInvalidOrderOrMixedParts() {
    #expect(PracticePassage(start: makeOccurrence(4), end: makeOccurrence(2)) == nil)
    #expect(PracticePassage(start: makeOccurrence(1, partID: "P1"), end: makeOccurrence(2, partID: "P2")) == nil)
}

@Test
func identityUsesSongAndRevision() {
    let songID = UUID()
    #expect(
        PracticeSongIdentity(songID: songID, scoreRevision: "a")
            != PracticeSongIdentity(songID: songID, scoreRevision: "b")
    )
}
