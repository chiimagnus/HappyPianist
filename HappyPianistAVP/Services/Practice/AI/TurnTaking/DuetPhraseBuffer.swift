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
        let phraseProvenance: CreativeDuetPhraseProvenance

        init(
            nowTimestampSeconds: TimeInterval,
            promptNotes: [ImprovDialogueNote],
            heldNotes: [HeldNoteState],
            heldNoteMIDIs: Set<Int>,
            lastUserEventTimestampSeconds: TimeInterval?,
            lastNoteOnTimestampSeconds: TimeInterval?,
            recentIOIMedianSeconds: TimeInterval?,
            recentVelocityTrend: Double,
            recentNoteDensityPerSecond: Double,
            activePitchCenter: Double?,
            phraseProvenance: CreativeDuetPhraseProvenance = .empty
        ) {
            self.nowTimestampSeconds = nowTimestampSeconds
            self.promptNotes = promptNotes
            self.heldNotes = heldNotes
            self.heldNoteMIDIs = heldNoteMIDIs
            self.lastUserEventTimestampSeconds = lastUserEventTimestampSeconds
            self.lastNoteOnTimestampSeconds = lastNoteOnTimestampSeconds
            self.recentIOIMedianSeconds = recentIOIMedianSeconds
            self.recentVelocityTrend = recentVelocityTrend
            self.recentNoteDensityPerSecond = recentNoteDensityPerSecond
            self.activePitchCenter = activePitchCenter
            self.phraseProvenance = phraseProvenance
        }
    }

    private struct OpenNote: Equatable {
        let startedAtTimestampSeconds: TimeInterval
        let velocity: Int
    }

    private struct RecordedNote: Equatable {
        let note: ImprovDialogueNote
    }

    private struct TimestampedProvenance: Equatable {
        let timestampSeconds: TimeInterval
        let provenance: CreativeDuetPhraseProvenance.Observation
    }

    private var openNotes: [Int: OpenNote] = [:]
    private var sustainedNotes: [Int: OpenNote] = [:]
    private var completedNotes: [RecordedNote] = []
    private var recordedProvenances: [TimestampedProvenance] = []
    private var lastUserEventTimestampSeconds: TimeInterval?
    private var lastNoteOnTimestampSeconds: TimeInterval?

    private static let maxHistorySeconds: TimeInterval = 12.0

    init() {}

    mutating func record(
        _ event: PerformanceObservationPhraseAdapter.PhraseEvent,
        sustainIsDown: Bool
    ) {
        let timestampSeconds = event.timestamp.seconds

        switch event.kind {
        case let .noteOn(midi, velocity):
            recordProvenance(event.provenance, at: timestampSeconds)
            guard let velocity else { return }
            recordNoteOn(
                midi: midi,
                velocity: velocity,
                timestampSeconds: timestampSeconds
            )
        case let .noteOff(midi):
            recordProvenance(event.provenance, at: timestampSeconds)
            recordNoteOff(midi: midi, timestampSeconds: timestampSeconds, sustainIsDown: sustainIsDown)
        case .allNotesOff:
            reset()
        case .controlChange:
            return
        }
    }

    mutating func releaseSustainedNotes(timestampSeconds: TimeInterval) {
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        for (midi, open) in sustainedNotes {
            appendCompletedNote(midi: midi, open: open, endedAtTimestampSeconds: timestampSeconds)
        }
        sustainedNotes.removeAll(keepingCapacity: true)
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
        var rawPromptNotes = completedNotes.filter { recorded in
            (recorded.note.time + recorded.note.duration) >= lookbackStart
        }
        rawPromptNotes.append(contentsOf: projectedOpenNotes(at: nowTimestampSeconds))
        rawPromptNotes.sort { lhs, rhs in
            if lhs.note.time != rhs.note.time { return lhs.note.time < rhs.note.time }
            return lhs.note.note < rhs.note.note
        }

        let promptNotes = makePromptNotes(
            from: rawPromptNotes,
            lookbackStart: lookbackStart,
            nowTimestampSeconds: nowTimestampSeconds,
            maxPromptSeconds: maxPromptSeconds
        )

        let recentStarts = rawPromptNotes
            .map(\.note.time)
            .filter { $0 >= nowTimestampSeconds - 2.4 }
            .sorted()
        let recentIOIValues = zip(recentStarts.dropFirst(), recentStarts).map { current, previous in
            max(0, current - previous)
        }
        let recentIOIMedianSeconds = Self.median(recentIOIValues)

        let densityWindowSeconds: TimeInterval = 1.2
        let recentDensityCount = rawPromptNotes.count(where: { $0.note.time >= nowTimestampSeconds - densityWindowSeconds })
        let recentNoteDensityPerSecond = Double(recentDensityCount) / densityWindowSeconds

        let recentVelocities = rawPromptNotes.suffix(8).map(\.note.velocity)
        let recentVelocityTrend = Self.velocityTrend(recentVelocities)

        let activePitchSource = heldStates.isEmpty == false
            ? heldStates.map { Double($0.midi) }
            : rawPromptNotes
            .filter { ($0.note.time + $0.note.duration) >= nowTimestampSeconds - 2.0 }
            .map { Double($0.note.note) }
        let activePitchCenter = activePitchSource.isEmpty ? nil : activePitchSource.reduce(0, +) / Double(activePitchSource.count)
        let provenance = CreativeDuetPhraseProvenance(
            observations: recordedProvenances
                .filter { $0.timestampSeconds >= lookbackStart }
                .map(\.provenance)
        )

        return Snapshot(
            nowTimestampSeconds: nowTimestampSeconds,
            promptNotes: promptNotes.map(\.note),
            heldNotes: heldStates,
            heldNoteMIDIs: Set(heldStates.map(\.midi)),
            lastUserEventTimestampSeconds: lastUserEventTimestampSeconds,
            lastNoteOnTimestampSeconds: lastNoteOnTimestampSeconds,
            recentIOIMedianSeconds: recentIOIMedianSeconds,
            recentVelocityTrend: recentVelocityTrend,
            recentNoteDensityPerSecond: recentNoteDensityPerSecond,
            activePitchCenter: activePitchCenter,
            phraseProvenance: provenance
        )
    }

    mutating func reset() {
        openNotes.removeAll(keepingCapacity: true)
        sustainedNotes.removeAll(keepingCapacity: true)
        completedNotes.removeAll(keepingCapacity: true)
        recordedProvenances.removeAll(keepingCapacity: true)
        lastUserEventTimestampSeconds = nil
        lastNoteOnTimestampSeconds = nil
    }

    private mutating func recordNoteOn(
        midi: Int,
        velocity: Int,
        timestampSeconds: TimeInterval
    ) {
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        lastUserEventTimestampSeconds = timestampSeconds
        lastNoteOnTimestampSeconds = timestampSeconds

        if let existing = openNotes.removeValue(forKey: midi) ?? sustainedNotes.removeValue(forKey: midi) {
            appendCompletedNote(midi: midi, open: existing, endedAtTimestampSeconds: timestampSeconds)
        }

        openNotes[midi] = OpenNote(
            startedAtTimestampSeconds: timestampSeconds,
            velocity: velocity
        )
    }

    private mutating func recordNoteOff(
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

    private mutating func appendCompletedNote(
        midi: Int,
        open: OpenNote,
        endedAtTimestampSeconds: TimeInterval
    ) {
        let endTimestampSeconds = max(endedAtTimestampSeconds, open.startedAtTimestampSeconds)
        completedNotes.append(
            RecordedNote(
                note: ImprovDialogueNote(
                    note: midi,
                    velocity: open.velocity,
                    time: open.startedAtTimestampSeconds,
                    duration: max(0.05, endTimestampSeconds - open.startedAtTimestampSeconds)
                )
            )
        )
    }

    private mutating func recordProvenance(
        _ provenance: CreativeDuetPhraseProvenance.Observation,
        at timestampSeconds: TimeInterval
    ) {
        pruneHistory(nowTimestampSeconds: timestampSeconds)
        recordedProvenances.append(
            TimestampedProvenance(timestampSeconds: timestampSeconds, provenance: provenance)
        )
    }

    private mutating func pruneHistory(nowTimestampSeconds: TimeInterval) {
        let cutoff = nowTimestampSeconds - Self.maxHistorySeconds
        completedNotes.removeAll { recorded in
            (recorded.note.time + recorded.note.duration) < cutoff
        }
        recordedProvenances.removeAll { $0.timestampSeconds < cutoff }
    }

    private func projectedOpenNotes(at nowTimestampSeconds: TimeInterval) -> [RecordedNote] {
        openNotes.merging(sustainedNotes) { _, sustained in sustained }.map { midi, open in
            RecordedNote(
                note: ImprovDialogueNote(
                    note: midi,
                    velocity: open.velocity,
                    time: open.startedAtTimestampSeconds,
                    duration: max(0.05, nowTimestampSeconds - open.startedAtTimestampSeconds)
                )
            )
        }
    }

    private func makePromptNotes(
        from notes: [RecordedNote],
        lookbackStart: TimeInterval,
        nowTimestampSeconds: TimeInterval,
        maxPromptSeconds: TimeInterval
    ) -> [RecordedNote] {
        guard notes.isEmpty == false else { return [] }

        let latestEnd = notes.map { $0.note.time + $0.note.duration }.max() ?? nowTimestampSeconds
        let windowStart = max(lookbackStart, latestEnd - max(0.5, maxPromptSeconds))
        let windowEnd = max(nowTimestampSeconds, latestEnd)

        return notes.compactMap { recorded in
            let noteStart = max(recorded.note.time, windowStart)
            let noteEnd = min(recorded.note.time + recorded.note.duration, windowEnd)
            guard noteEnd > noteStart else { return nil }
            return RecordedNote(
                note: ImprovDialogueNote(
                    note: recorded.note.note,
                    velocity: recorded.note.velocity,
                    time: max(0, noteStart - windowStart),
                    duration: max(0.05, noteEnd - noteStart)
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.note.time != rhs.note.time { return lhs.note.time < rhs.note.time }
            return lhs.note.note < rhs.note.note
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
