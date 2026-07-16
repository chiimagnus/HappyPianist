import Foundation

struct PracticeHistoricalPreferencesResolver {
    nonisolated func resolve(
        identity: PracticeSongIdentity,
        history: PracticeSongHistory
    ) -> PracticeLaunchRestorePolicy {
        let progresses = history.progresses.filter { $0.identity.songID == identity.songID }
        guard progresses.contains(where: { $0.identity == identity }) == false else {
            return .exactAvailable
        }

        var preferredByIdentity: [PracticeSongIdentity: SongPracticeProgress] = [:]
        for progress in progresses where progress.activeConfiguration != nil {
            if let current = preferredByIdentity[progress.identity],
               PracticeProgressRecordOrder.preferred(current, over: progress)
            {
                continue
            }
            preferredByIdentity[progress.identity] = progress
        }

        guard let preferred = preferredByIdentity.values.reduce(nil, Self.preferredCandidate),
              let configuration = preferred.activeConfiguration
        else {
            return .freshDefaults
        }
        return .historicalPreferences(
            PracticeHistoricalPreferences(
                handMode: configuration.handMode,
                tempoScale: configuration.tempoScale,
                loopEnabled: configuration.loopEnabled,
                requiredSuccesses: configuration.requiredSuccesses
            )
        )
    }

    private nonisolated static func preferredCandidate(
        _ current: SongPracticeProgress?,
        _ candidate: SongPracticeProgress
    ) -> SongPracticeProgress? {
        guard let current else { return candidate }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt ? candidate : current
        }
        if candidate.identity.scoreRevision != current.identity.scoreRevision {
            return candidate.identity.scoreRevision > current.identity.scoreRevision ? candidate : current
        }
        return canonicalPreferences(candidate) > canonicalPreferences(current) ? candidate : current
    }

    private nonisolated static func canonicalPreferences(_ progress: SongPracticeProgress) -> String {
        guard let configuration = progress.activeConfiguration else { return "" }
        let tempoBits = String(configuration.tempoScale.bitPattern, radix: 16)
        return [
            configuration.handMode.rawValue,
            tempoBits,
            configuration.loopEnabled ? "1" : "0",
            String(configuration.requiredSuccesses),
        ].joined(separator: "|")
    }
}
