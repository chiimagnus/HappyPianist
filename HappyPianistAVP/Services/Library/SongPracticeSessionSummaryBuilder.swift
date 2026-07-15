import Foundation

struct SongPracticeSessionSummaryBuilder: Sendable {
    func build(
        songID: UUID,
        sessions: [PracticeSessionRecord],
        viewedAt: Date,
        viewingTimeZone: TimeZone
    ) -> SongPracticeSessionSummary {
        let matchingSessions = sessions.filter { $0.songID == songID }
        guard matchingSessions.isEmpty == false else {
            return SongPracticeSessionSummary(
                latestPracticeEndedAt: nil,
                totalActiveDurationMilliseconds: 0,
                sessionCount: 0,
                streak: nil
            )
        }

        let latestPracticeEndedAt = matchingSessions.compactMap(\.endedAt).max()
        let totalActiveDurationMilliseconds = matchingSessions.reduce(into: Int64(0)) { total, session in
            let (sum, overflow) = total.addingReportingOverflow(
                session.activePracticeDurationMilliseconds
            )
            total = overflow ? .max : sum
        }
        let uniquePracticeDays = Set(matchingSessions.map(\.practiceDay))
        let dayOrdinals = Set(uniquePracticeDays.compactMap(Self.dayOrdinal))
        let latestPracticeDay = matchingSessions.max(by: Self.sessionStartedEarlier)?.practiceDay
        let streak = latestPracticeDay.flatMap { latestDay in
            Self.streak(
                endingAt: latestDay,
                dayOrdinals: dayOrdinals,
                viewedAt: viewedAt,
                viewingTimeZone: viewingTimeZone
            )
        }

        return SongPracticeSessionSummary(
            latestPracticeEndedAt: latestPracticeEndedAt,
            totalActiveDurationMilliseconds: totalActiveDurationMilliseconds,
            sessionCount: matchingSessions.count,
            streak: streak
        )
    }

    private static func sessionStartedEarlier(
        _ lhs: PracticeSessionRecord,
        _ rhs: PracticeSessionRecord
    ) -> Bool {
        if lhs.practiceStartedAt != rhs.practiceStartedAt {
            return lhs.practiceStartedAt < rhs.practiceStartedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func streak(
        endingAt latestDay: PracticeLocalDay,
        dayOrdinals: Set<Int>,
        viewedAt: Date,
        viewingTimeZone: TimeZone
    ) -> SongPracticeStreak? {
        guard let latestOrdinal = dayOrdinal(latestDay) else { return nil }
        var dayCount = 0
        while dayOrdinals.contains(latestOrdinal - dayCount) {
            dayCount += 1
        }
        guard dayCount > 0,
              let viewedDay = localDay(for: viewedAt, in: viewingTimeZone),
              let viewedOrdinal = dayOrdinal(viewedDay)
        else {
            return nil
        }
        let age = viewedOrdinal - latestOrdinal
        return SongPracticeStreak(
            dayCount: dayCount,
            recency: (0 ... 1).contains(age) ? .current : .recent
        )
    }

    private static func localDay(for date: Date, in timeZone: TimeZone) -> PracticeLocalDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        return PracticeLocalDay(
            year: year,
            month: month,
            day: day,
            timeZoneIdentifier: timeZone.identifier
        )
    }

    private static func dayOrdinal(_ day: PracticeLocalDay) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(
            year: day.year,
            month: day.month,
            day: day.day
        )) else {
            return nil
        }
        return calendar.dateComponents(
            [.day],
            from: Date(timeIntervalSinceReferenceDate: 0),
            to: date
        ).day
    }
}
