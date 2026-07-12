import Foundation

struct PracticeHotspotPolicy {
    func hotspot(in facts: [MeasurePracticeFacts]) -> PracticeHotspot? {
        facts.enumerated()
            .compactMap { offset, facts -> (Int, MeasurePracticeFacts)? in
                guard facts.failedAttempts > 0, facts.recentIssue != nil else { return nil }
                return (offset, facts)
            }
            .max { lhs, rhs in
                if lhs.1.failedAttempts != rhs.1.failedAttempts {
                    return lhs.1.failedAttempts < rhs.1.failedAttempts
                }
                if lhs.1.lastAttemptAt != rhs.1.lastAttemptAt {
                    return (lhs.1.lastAttemptAt ?? .distantPast) < (rhs.1.lastAttemptAt ?? .distantPast)
                }
                return lhs.0 > rhs.0
            }
            .map { _, facts in
                PracticeHotspot(
                    sourceMeasureID: facts.sourceMeasureID,
                    failedAttempts: facts.failedAttempts
                )
            }
    }
}
