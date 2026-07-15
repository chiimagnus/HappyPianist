import Foundation
@testable import HappyPianistAVP
import Testing

private let sessionSummaryBuilder = SongPracticeSessionSummaryBuilder()

@Test
func sessionSummaryIsEmptyWithoutValidSessions() {
    #expect(sessionSummaryBuilder.build(
        songID: UUID(),
        sessions: [],
        viewedAt: Date(timeIntervalSince1970: 0),
        viewingTimeZone: TimeZone(identifier: "Asia/Singapore")!
    ) == SongPracticeSessionSummary(
        latestPracticeEndedAt: nil,
        totalActiveDurationMilliseconds: 0,
        sessionCount: 0,
        streak: nil
    ))
}

@Test
func sessionSummaryCountsEverySessionButDeduplicatesPracticeDays() throws {
    let songID = UUID()
    let otherSongID = UUID()
    let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
    let first = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        startedAt: 100,
        endedAt: 130,
        activeMilliseconds: 30_000
    )
    let second = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        startedAt: 200,
        endedAt: 245,
        activeMilliseconds: 45_000
    )
    let ignored = try makeSummarySession(
        songID: otherSongID,
        day: (2026, 7, 15),
        startedAt: 300,
        endedAt: 400,
        activeMilliseconds: 100_000
    )

    #expect(sessionSummaryBuilder.build(
        songID: songID,
        sessions: [ignored, second, first],
        viewedAt: date(2026, 7, 15, timeZone: singapore),
        viewingTimeZone: singapore
    ) == SongPracticeSessionSummary(
        latestPracticeEndedAt: Date(timeIntervalSince1970: 245),
        totalActiveDurationMilliseconds: 75_000,
        sessionCount: 2,
        streak: SongPracticeStreak(dayCount: 1, recency: .current)
    ))
}

@Test
func sessionSummaryUsesCapturedDayAcrossMidnightAndTimeZoneChanges() throws {
    let songID = UUID()
    let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let first = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 13),
        dayTimeZone: losAngeles,
        startedAt: 100,
        endedAt: 200,
        activeMilliseconds: 1_000
    )
    let acrossMidnight = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        dayTimeZone: tokyo,
        startedAt: 300,
        endedAt: 400,
        activeMilliseconds: 2_000,
        termination: .recoveredAfterInterruption
    )

    let summary = sessionSummaryBuilder.build(
        songID: songID,
        sessions: [acrossMidnight, first],
        viewedAt: date(2026, 7, 15, timeZone: singapore),
        viewingTimeZone: singapore
    )

    #expect(summary.streak == SongPracticeStreak(dayCount: 2, recency: .current))
    #expect(summary.latestPracticeEndedAt == Date(timeIntervalSince1970: 400))
}

@Test
func sessionSummaryMarksOlderStreakAsRecentAndIncludesOpenCheckpoint() throws {
    let songID = UUID()
    let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
    let open = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 10),
        startedAt: 500,
        endedAt: nil,
        activeMilliseconds: 20_000,
        termination: .open
    )

    #expect(sessionSummaryBuilder.build(
        songID: songID,
        sessions: [open],
        viewedAt: date(2026, 7, 15, timeZone: singapore),
        viewingTimeZone: singapore
    ) == SongPracticeSessionSummary(
        latestPracticeEndedAt: nil,
        totalActiveDurationMilliseconds: 20_000,
        sessionCount: 1,
        streak: SongPracticeStreak(dayCount: 1, recency: .recent)
    ))
}

private func makeSummarySession(
    songID: UUID,
    day: (Int, Int, Int),
    dayTimeZone: TimeZone = TimeZone(identifier: "Asia/Singapore")!,
    startedAt: TimeInterval,
    endedAt: TimeInterval?,
    activeMilliseconds: Int64,
    termination: PracticeSessionTermination = .normal
) throws -> PracticeSessionRecord {
    let practiceDay = try #require(PracticeLocalDay(
        year: day.0,
        month: day.1,
        day: day.2,
        timeZoneIdentifier: dayTimeZone.identifier
    ))
    return try #require(PracticeSessionRecord(
        id: UUID(),
        songID: songID,
        scoreRevision: "revision",
        windowOpenedAt: Date(timeIntervalSince1970: startedAt - 10),
        practiceStartedAt: Date(timeIntervalSince1970: startedAt),
        practiceDay: practiceDay,
        endedAt: endedAt.map(Date.init(timeIntervalSince1970:)),
        lastPersistedAt: Date(timeIntervalSince1970: endedAt ?? startedAt),
        practiceWindowDurationMilliseconds: max(activeMilliseconds, 30_000),
        activePracticeDurationMilliseconds: activeMilliseconds,
        termination: termination
    ))
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    timeZone: TimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}
