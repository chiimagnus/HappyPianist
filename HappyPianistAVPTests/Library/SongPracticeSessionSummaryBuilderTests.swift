import Foundation
@testable import HappyPianistAVP
import Testing

private let sessionSummaryBuilder = SongPracticeSessionSummaryBuilder()

@Test
func sessionSummaryIsEmptyWithoutValidSessions() throws {
    #expect(try sessionSummaryBuilder.build(
        songID: UUID(),
        sessions: [],
        viewedAt: Date(timeIntervalSince1970: 0),
        viewingTimeZone: #require(TimeZone(identifier: "Asia/Singapore"))
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
    let firstEnd = date(2026, 7, 14, hour: 10, minute: 30, timeZone: singapore)
    let secondEnd = date(2026, 7, 14, hour: 11, minute: 45, timeZone: singapore)
    let first = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        startedAt: date(2026, 7, 14, hour: 10, timeZone: singapore),
        endedAt: firstEnd,
        activeMilliseconds: 30000
    )
    let second = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        startedAt: date(2026, 7, 14, hour: 11, timeZone: singapore),
        endedAt: secondEnd,
        activeMilliseconds: 45000
    )
    let ignored = try makeSummarySession(
        songID: otherSongID,
        day: (2026, 7, 15),
        startedAt: date(2026, 7, 15, hour: 9, timeZone: singapore),
        endedAt: date(2026, 7, 15, hour: 10, timeZone: singapore),
        activeMilliseconds: 100_000
    )

    #expect(sessionSummaryBuilder.build(
        songID: songID,
        sessions: [ignored, second, first],
        viewedAt: date(2026, 7, 15, timeZone: singapore),
        viewingTimeZone: singapore
    ) == SongPracticeSessionSummary(
        latestPracticeEndedAt: secondEnd,
        totalActiveDurationMilliseconds: 75000,
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
        startedAt: date(2026, 7, 13, hour: 23, minute: 30, timeZone: losAngeles),
        endedAt: date(2026, 7, 13, hour: 23, minute: 45, timeZone: losAngeles),
        activeMilliseconds: 1000
    )
    let acrossMidnightEnd = date(2026, 7, 15, hour: 0, minute: 10, timeZone: tokyo)
    let acrossMidnight = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        dayTimeZone: tokyo,
        startedAt: date(2026, 7, 14, hour: 23, minute: 50, timeZone: tokyo),
        endedAt: acrossMidnightEnd,
        activeMilliseconds: 2000,
        termination: .recoveredAfterInterruption
    )

    let summary = sessionSummaryBuilder.build(
        songID: songID,
        sessions: [acrossMidnight, first],
        viewedAt: date(2026, 7, 15, timeZone: singapore),
        viewingTimeZone: singapore
    )

    #expect(summary.streak == SongPracticeStreak(dayCount: 2, recency: .current))
    #expect(summary.latestPracticeEndedAt == acrossMidnightEnd)
}

@Test
func sessionSummaryStartsStreakFromLatestPersistedDayWhenWallClockOrderReverses() throws {
    let songID = UUID()
    let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let latestPersistedDay = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 15),
        dayTimeZone: tokyo,
        startedAt: date(2026, 7, 15, hour: 0, minute: 10, timeZone: tokyo),
        endedAt: date(2026, 7, 15, hour: 0, minute: 20, timeZone: tokyo),
        activeMilliseconds: 1000
    )
    let laterAbsoluteSessionOnEarlierLocalDay = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 14),
        dayTimeZone: losAngeles,
        startedAt: date(2026, 7, 14, hour: 23, minute: 30, timeZone: losAngeles),
        endedAt: date(2026, 7, 14, hour: 23, minute: 40, timeZone: losAngeles),
        activeMilliseconds: 1000
    )

    let summary = sessionSummaryBuilder.build(
        songID: songID,
        sessions: [latestPersistedDay, laterAbsoluteSessionOnEarlierLocalDay],
        viewedAt: date(2026, 7, 16, timeZone: singapore),
        viewingTimeZone: singapore
    )

    #expect(summary.streak == SongPracticeStreak(dayCount: 2, recency: .current))
}

@Test
func sessionSummaryUsesViewingTimeZoneForStreakRecency() throws {
    let songID = UUID()
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    let endedAt = date(2026, 7, 15, hour: 0, minute: 30, timeZone: tokyo)
    let session = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 15),
        dayTimeZone: tokyo,
        startedAt: date(2026, 7, 15, hour: 0, minute: 20, timeZone: tokyo),
        endedAt: endedAt,
        activeMilliseconds: 1000
    )

    let summary = sessionSummaryBuilder.build(
        songID: songID,
        sessions: [session],
        viewedAt: date(2026, 7, 14, hour: 12, timeZone: losAngeles),
        viewingTimeZone: losAngeles
    )

    #expect(summary.latestPracticeEndedAt == endedAt)
    #expect(summary.streak == SongPracticeStreak(dayCount: 1, recency: .current))
}

@Test
func sessionSummaryMarksOlderStreakAsRecentAndIncludesOpenCheckpoint() throws {
    let songID = UUID()
    let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
    let startedAt = date(2026, 7, 10, hour: 10, timeZone: singapore)
    let open = try makeSummarySession(
        songID: songID,
        day: (2026, 7, 10),
        startedAt: startedAt,
        endedAt: nil,
        activeMilliseconds: 20000,
        termination: .open
    )

    #expect(sessionSummaryBuilder.build(
        songID: songID,
        sessions: [open],
        viewedAt: date(2026, 7, 15, timeZone: singapore),
        viewingTimeZone: singapore
    ) == SongPracticeSessionSummary(
        latestPracticeEndedAt: nil,
        totalActiveDurationMilliseconds: 20000,
        sessionCount: 1,
        streak: SongPracticeStreak(dayCount: 1, recency: .recent)
    ))
}

private func makeSummarySession(
    songID: UUID,
    day: (Int, Int, Int),
    dayTimeZone: TimeZone = TimeZone(identifier: "Asia/Singapore")!,
    startedAt: Date,
    endedAt: Date?,
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
        windowOpenedAt: startedAt.addingTimeInterval(-10),
        practiceStartedAt: startedAt,
        practiceDay: practiceDay,
        endedAt: endedAt,
        lastPersistedAt: endedAt ?? startedAt,
        practiceWindowDurationMilliseconds: max(activeMilliseconds, 30000),
        activePracticeDurationMilliseconds: activeMilliseconds,
        termination: termination
    ))
}

private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 12,
    minute: Int = 0,
    timeZone: TimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    ))!
}
