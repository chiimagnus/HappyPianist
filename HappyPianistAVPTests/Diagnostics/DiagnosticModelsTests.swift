import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func diagnosticFileReferenceRejectsAbsoluteAndTraversalPaths() {
    #expect(DiagnosticFileReference(fileName: "score.musicxml", relativePath: "/Users/test/score.musicxml") == nil)
    #expect(DiagnosticFileReference(fileName: "score.musicxml", relativePath: "SongLibrary/../score.musicxml") == nil)
    #expect(DiagnosticFileReference(fileName: "score.musicxml", relativePath: "file://score.musicxml") == nil)
}

@Test
func diagnosticFileReferenceNormalizesSafeRelativePath() throws {
    let reference = try #require(
        DiagnosticFileReference(
            fileName: "/tmp/example.musicxml",
            relativePath: "SongLibrary\\scores\\example.musicxml"
        )
    )
    #expect(reference.fileName == "example.musicxml")
    #expect(reference.relativePath == "SongLibrary/scores/example.musicxml")
}

@Test
func diagnosticEventTextRepresentationContainsStableFields() throws {
    let reference = try #require(
        DiagnosticFileReference(
            fileName: "example.musicxml",
            relativePath: "SongLibrary/scores/example.musicxml"
        )
    )
    let eventID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let event = DiagnosticEvent(
        id: eventID,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        severity: .error,
        code: .practiceXMLParseFailed,
        category: .practicePreparation,
        stage: "musicXMLParsing",
        summary: "无法解析 MusicXML",
        reason: "Opening and ending tag mismatch",
        songID: UUID(uuidString: "00000000-0000-0000-0000-000000000002"),
        file: reference,
        sourceLocation: DiagnosticSourceLocation(line: 42, column: 7),
        persistence: .exportable
    )

    let text = event.textRepresentation
    #expect(text.contains("code: PRACTICE_XML_PARSE_FAILED"))
    #expect(text.contains("relativePath: SongLibrary/scores/example.musicxml"))
    #expect(text.contains("line: 42"))
    #expect(text.contains("column: 7"))
    #expect(text.contains("/Users/") == false)
}

@Test
func diagnosticEventCodableRoundTrips() throws {
    let event = DiagnosticEvent(
        timestamp: Date(timeIntervalSince1970: 1_700_000_000),
        severity: .warning,
        code: .diagnosticsStoreWriteFailed,
        category: .diagnostics,
        stage: "append",
        summary: "写入失败",
        reason: "disk full",
        persistence: .systemOnly
    )

    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(DiagnosticEvent.self, from: data)
    #expect(decoded == event)
}

@Test
func diagnosticsDateTextBuildsStableTokensWithoutSharedFormatters() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let date = try #require(
        calendar.date(
            from: DateComponents(
                year: 2026,
                month: 7,
                day: 2,
                hour: 3,
                minute: 4,
                second: 5
            )
        )
    )

    #expect(DiagnosticsDateText.dayToken(date, calendar: calendar) == "2026-07-02")
    #expect(DiagnosticsDateText.archiveToken(date, calendar: calendar) == "20260702-030405")
    #expect(DiagnosticsDateText.iso8601(date).hasPrefix("2026-07-02T03:04:05"))
}

@Test
func pianoPerformanceDiagnosticUsesOnlyLowCardinalityWhitelistedFields() {
    let sample = PianoPerformanceDiagnosticSample(
        stage: .plan,
        outcome: .mismatch,
        capability: .performancePlan,
        itemCount: 12,
        durationBucket: .underFiftyMilliseconds,
        exportable: true
    )
    let event = sample.diagnosticEvent

    #expect(event.code == .pianoPerformancePipeline)
    #expect(event.category == .pianoPerformance)
    #expect(event.persistence == .exportable)
    #expect(event.reason == "outcome=mismatch;capability=performancePlan;count=12;duration=underFiftyMilliseconds")
    #expect(event.file == nil)
    #expect(event.safeFileName == nil)
    #expect(event.reason.contains("/") == false)
    #expect(event.reason.contains(".musicxml") == false)
}

@Test
func pianoPerformanceDurationBucketsAreStable() {
    #expect(PianoPerformanceDurationBucket(seconds: 0.001) == .underTenMilliseconds)
    #expect(PianoPerformanceDurationBucket(seconds: 0.02) == .underFiftyMilliseconds)
    #expect(PianoPerformanceDurationBucket(seconds: 0.1) == .underTwoHundredMilliseconds)
    #expect(PianoPerformanceDurationBucket(seconds: 0.5) == .underOneSecond)
    #expect(PianoPerformanceDurationBucket(seconds: 2) == .oneSecondOrMore)
}

@Test
func pianoOutputMetricsAggregateTimingFailuresAndPrivacySafeFields() {
    var metrics = PianoOutputMetricsAccumulator()
    metrics.record(PianoOutputTimestampObservation(
        scheduledAtSeconds: 1,
        submittedAtSeconds: 0.95,
        acknowledgedAtSeconds: 1.02
    ))
    metrics.record(PianoOutputTimestampObservation(
        scheduledAtSeconds: 2,
        submittedAtSeconds: 2.015,
        acknowledgedAtSeconds: nil
    ))
    metrics.recordDropped(count: 2)
    metrics.recordCancelled(count: 1)
    metrics.recordReset(succeeded: false, preventsStuckNotes: true)

    let measurementMetadata = PianoOutputMeasurementMetadata(
        calibrationID: UUID(uuidString: "00000000-0000-0000-0000-000000000010"),
        calibrationVersion: 2,
        sampleCount: 48,
        deviceModel: "Apple Vision Pro",
        operatingSystemVersion: "visionOS 26.4",
        audioRoute: .usb
    )
    let snapshot = metrics.snapshot(
        capability: .externalMIDI,
        measurementMetadata: measurementMetadata
    )
    #expect(snapshot.scheduledCount == 5)
    #expect(snapshot.submittedCount == 2)
    #expect(snapshot.acknowledgedCount == 1)
    #expect(snapshot.lateCount == 1)
    #expect(snapshot.droppedCount == 2)
    #expect(snapshot.cancelledCount == 1)
    #expect(snapshot.resetFailedCount == 1)
    #expect(snapshot.stuckNotePreventionCount == 0)
    #expect(snapshot.submissionLatencyBuckets[.underTenMilliseconds] == 1)
    #expect(snapshot.submissionLatencyBuckets[.underFiftyMilliseconds] == 1)
    #expect(snapshot.acknowledgementLatencyBuckets[.underFiftyMilliseconds] == 1)
    #expect(snapshot.jitterBuckets[.underTwoHundredMilliseconds] == 1)

    let event = snapshot.diagnosticEvent
    #expect(event.persistence == .exportable)
    #expect(event.stage == "playback.outputMetrics")
    #expect(event.reason.contains("capability=externalMIDI"))
    #expect(event.reason.contains("scheduled=5"))
    #expect(event.reason.contains("dropped=2"))
    #expect(event.reason.contains("cancelled=1"))
    #expect(event.reason.contains("calibrationVersion=2"))
    #expect(event.reason.contains("sampleCount=48"))
    #expect(event.reason.contains("deviceModel=Apple Vision Pro"))
    #expect(event.reason.contains("osVersion=visionOS 26.4"))
    #expect(event.reason.contains("audioRoute=usb"))
    #expect(event.reason.contains("/Users/") == false)
    #expect(event.reason.contains(".musicxml") == false)

    let unsafeMetadata = PianoOutputMeasurementMetadata(
        deviceModel: "/Users/test",
        operatingSystemVersion: "visionOS 26.4"
    )
    #expect(unsafeMetadata.deviceModel == nil)

    metrics.recordReset(succeeded: true, preventsStuckNotes: true)
    let successfulResetSnapshot = metrics.snapshot(capability: .externalMIDI)
    #expect(successfulResetSnapshot.resetSucceededCount == 1)
    #expect(successfulResetSnapshot.stuckNotePreventionCount == 1)
}
