import Foundation

struct SongPracticeSessionSummaryBuilder {
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
        let latestPracticeActivityAt = matchingSessions.map { session in
            session.endedAt ?? session.lastPersistedAt
        }.max()
        let totalActiveDurationMilliseconds = matchingSessions.reduce(into: Int64(0)) { total, session in
            let (sum, overflow) = total.addingReportingOverflow(
                session.activePracticeDurationMilliseconds
            )
            total = overflow ? .max : sum
        }
        let dayOrdinals = Set(matchingSessions.compactMap { Self.dayOrdinal($0.practiceDay) })
        let streak = dayOrdinals.max().flatMap { latestOrdinal in
            Self.streak(
                endingAt: latestOrdinal,
                dayOrdinals: dayOrdinals,
                latestPracticeActivityAt: latestPracticeActivityAt,
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

    private static func streak(
        endingAt latestOrdinal: Int,
        dayOrdinals: Set<Int>,
        latestPracticeActivityAt: Date?,
        viewedAt: Date,
        viewingTimeZone: TimeZone
    ) -> SongPracticeStreak? {
        var dayCount = 0
        while dayOrdinals.contains(latestOrdinal - dayCount) {
            dayCount += 1
        }
        guard dayCount > 0,
              let latestPracticeActivityAt,
              let latestViewedDay = localDay(
                  for: latestPracticeActivityAt,
                  in: viewingTimeZone
              ),
              let latestViewedOrdinal = dayOrdinal(latestViewedDay),
              let viewedDay = localDay(for: viewedAt, in: viewingTimeZone),
              let viewedOrdinal = dayOrdinal(viewedDay)
        else {
            return nil
        }
        let age = viewedOrdinal - latestViewedOrdinal
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
