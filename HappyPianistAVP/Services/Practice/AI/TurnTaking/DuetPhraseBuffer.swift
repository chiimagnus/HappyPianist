import Foundation

/// Continuous-duet note context. This buffer never waits for a phrase flush.
/// It keeps recent notes, current held notes, and can project a rolling prompt at any time.
struct DuetPhraseBuffer {
    struct HeldNoteState: Equatable {
        let midi: Int
        let velocity: Int
        let startedAtTimestampSeconds: TimeInterval
    }

    struct Snapshot: Equatable {
        let nowTimestampSeconds: TimeInterval
        let promptNotes: [ImprovDialogueNote]
        let heldNotes: [HeldNoteState]
        let heldNoteMIDIs: Set<Int>
        let lastUserEventTimestampSeconds: TimeInterval?
        let lastNoteOnTimestampSeconds: TimeInterval?
        let recentIOIMedianSeconds: TimeInterval?
        let recentVelocityTrend: Double
        let recentNoteDensityPerSecond: Double
        let activePitchCenter: Double?
    }

    private struct OpenNote: Equatable {
        let startedAtTimestampSeconds: TimeInterval
        let velocity: Int
    }

    private var openNotes: [Int: OpenNote] = [:]
    private var sustainedNotes: [Int: OpenNote] = [:]
    private var completedNotes: [ImprovDialogueNote] = []
    private var lastUserEventTimestampSeconds: TimeInterval?
    private var lastNoteOnTimestampSeconds: TimeInterval?

    private static let maxHistorySeconds: TimeInterval = 12.0

    init() {}

    mutating func recordNoteOn(midi: Int, velocity: Int, timestampSeconds: TimeInterval) {
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        lastUserEventTimestampSeconds = timestampSeconds
        lastNoteOnTimestampSeconds = timestampSeconds

        if let existing = openNotes.removeValue(forKey: midi) ?? sustainedNotes.removeValue(forKey: midi) {
            appendCompletedNote(midi: midi, open: existing, endedAtTimestampSeconds: timestampSeconds)
        }

        openNotes[midi] = OpenNote(startedAtTimestampSeconds: timestampSeconds, velocity: velocity)
    }

    mutating func recordNoteOff(
        midi: Int,
        timestampSeconds: TimeInterval,
        sustainIsDown: Bool
    ) {
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        lastUserEventTimestampSeconds = timestampSeconds

        guard let open = openNotes.removeValue(forKey: midi) else { return }
        if sustainIsDown {
            sustainedNotes[midi] = open
            return
        }
        appendCompletedNote(midi: midi, open: open, endedAtTimestampSeconds: timestampSeconds)
    }

    mutating func releaseSustainedNotes(timestampSeconds: TimeInterval) {
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        for (midi, open) in sustainedNotes {
            appendCompletedNote(midi: midi, open: open, endedAtTimestampSeconds: timestampSeconds)
        }
        sustainedNotes.removeAll(keepingCapacity: true)
    }

    private mutating func appendCompletedNote(
        midi: Int,
        open: OpenNote,
        endedAtTimestampSeconds: TimeInterval
    ) {
        let endTimestampSeconds = max(endedAtTimestampSeconds, open.startedAtTimestampSeconds)
        completedNotes.append(
            ImprovDialogueNote(
                note: midi,
                velocity: open.velocity,
                time: open.startedAtTimestampSeconds,
                duration: max(0.05, endTimestampSeconds - open.startedAtTimestampSeconds)
            )
        )
    }

    mutating func snapshot(
        nowTimestampSeconds: TimeInterval,
        lookbackSeconds: TimeInterval,
        maxPromptSeconds: TimeInterval
    ) -> Snapshot {
        pruneHistory(nowTimestampSeconds: nowTimestampSeconds)

        let soundingNotes = openNotes.merging(sustainedNotes) { _, sustained in sustained }
        let heldStates = soundingNotes
            .map { midi, open in
                HeldNoteState(midi: midi, velocity: open.velocity, startedAtTimestampSeconds: open.startedAtTimestampSeconds)
            }
            .sorted { lhs, rhs in
                if lhs.startedAtTimestampSeconds != rhs.startedAtTimestampSeconds {
                    return lhs.startedAtTimestampSeconds < rhs.startedAtTimestampSeconds
                }
                return lhs.midi < rhs.midi
            }

        let lookbackStart = max(0, nowTimestampSeconds - max(0, lookbackSeconds))
        var rawPromptNotes = completedNotes.filter { note in
            (note.time + note.duration) >= lookbackStart
        }
        rawPromptNotes.append(contentsOf: projectedOpenNotes(at: nowTimestampSeconds))
        rawPromptNotes.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }

        let promptNotes = makePromptNotes(
            from: rawPromptNotes,
            lookbackStart: lookbackStart,
            nowTimestampSeconds: nowTimestampSeconds,
            maxPromptSeconds: maxPromptSeconds
        )

        let recentStarts = rawPromptNotes
            .map(\.time)
            .filter { $0 >= nowTimestampSeconds - 2.4 }
            .sorted()
        let recentIOIValues = zip(recentStarts.dropFirst(), recentStarts).map { current, previous in
            max(0, current - previous)
        }
        let recentIOIMedianSeconds = Self.median(recentIOIValues)

        let densityWindowSeconds: TimeInterval = 1.2
        let recentDensityCount = rawPromptNotes.count(where: { $0.time >= nowTimestampSeconds - densityWindowSeconds })
        let recentNoteDensityPerSecond = Double(recentDensityCount) / densityWindowSeconds

        let recentVelocities = rawPromptNotes.suffix(8).map(\.velocity)
        let recentVelocityTrend = Self.velocityTrend(recentVelocities)

        let activePitchSource = heldStates.isEmpty == false
            ? heldStates.map { Double($0.midi) }
            : rawPromptNotes
            .filter { ($0.time + $0.duration) >= nowTimestampSeconds - 2.0 }
            .map { Double($0.note) }
        let activePitchCenter = activePitchSource.isEmpty ? nil : activePitchSource.reduce(0, +) / Double(activePitchSource.count)

        return Snapshot(
            nowTimestampSeconds: nowTimestampSeconds,
            promptNotes: promptNotes,
            heldNotes: heldStates,
            heldNoteMIDIs: Set(heldStates.map(\.midi)),
            lastUserEventTimestampSeconds: lastUserEventTimestampSeconds,
            lastNoteOnTimestampSeconds: lastNoteOnTimestampSeconds,
            recentIOIMedianSeconds: recentIOIMedianSeconds,
            recentVelocityTrend: recentVelocityTrend,
            recentNoteDensityPerSecond: recentNoteDensityPerSecond,
            activePitchCenter: activePitchCenter
        )
    }

    mutating func reset() {
        openNotes.removeAll(keepingCapacity: true)
        sustainedNotes.removeAll(keepingCapacity: true)
        completedNotes.removeAll(keepingCapacity: true)
        lastUserEventTimestampSeconds = nil
        lastNoteOnTimestampSeconds = nil
    }

    private mutating func pruneHistory(nowTimestampSeconds: TimeInterval) {
        let cutoff = nowTimestampSeconds - Self.maxHistorySeconds
        completedNotes.removeAll { note in
            (note.time + note.duration) < cutoff
        }
    }

    private func projectedOpenNotes(at nowTimestampSeconds: TimeInterval) -> [ImprovDialogueNote] {
        openNotes.merging(sustainedNotes) { _, sustained in sustained }.map { midi, open in
            ImprovDialogueNote(
                note: midi,
                velocity: open.velocity,
                time: open.startedAtTimestampSeconds,
                duration: max(0.05, nowTimestampSeconds - open.startedAtTimestampSeconds)
            )
        }
    }

    private func makePromptNotes(
        from notes: [ImprovDialogueNote],
        lookbackStart: TimeInterval,
        nowTimestampSeconds: TimeInterval,
        maxPromptSeconds: TimeInterval
    ) -> [ImprovDialogueNote] {
        guard notes.isEmpty == false else { return [] }

        let latestEnd = notes.map { $0.time + $0.duration }.max() ?? nowTimestampSeconds
        let windowStart = max(lookbackStart, latestEnd - max(0.5, maxPromptSeconds))
        let windowEnd = max(nowTimestampSeconds, latestEnd)

        return notes.compactMap { note in
            let noteStart = max(note.time, windowStart)
            let noteEnd = min(note.time + note.duration, windowEnd)
            guard noteEnd > noteStart else { return nil }
            return ImprovDialogueNote(
                note: note.note,
                velocity: note.velocity,
                time: max(0, noteStart - windowStart),
                duration: max(0.05, noteEnd - noteStart)
            )
        }
        .sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard values.isEmpty == false else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func velocityTrend(_ velocities: [Int]) -> Double {
        guard velocities.count >= 2 else { return 0 }
        let midpoint = velocities.count / 2
        let firstHalf = velocities.prefix(midpoint)
        let secondHalf = velocities.suffix(velocities.count - midpoint)
        guard firstHalf.isEmpty == false, secondHalf.isEmpty == false else { return 0 }
        let firstAverage = Double(firstHalf.reduce(0, +)) / Double(firstHalf.count)
        let secondAverage = Double(secondHalf.reduce(0, +)) / Double(secondHalf.count)
        return secondAverage - firstAverage
    }
}
