import Foundation
import ImprovProtocol

/// A pure-logic state machine which mirrors A.I. Duet's turn-taking behavior (`AI.js`):
/// - held-notes gate: only considers sending when all held notes are released
/// - phrase start tracking: first note-on starts a phrase timer
/// - long phrase: if phrase wall-clock duration > 3s at release-all, send immediately
/// - short phrase: otherwise schedule send at (releaseAll + 600ms)
/// - any new note-on cancels a pending scheduled send
struct DuetTurnTakingCore: Sendable {
    enum Event: Equatable, Sendable {
        case noteOn(note: Int, velocity: Int, timestampSeconds: TimeInterval)
        case noteOff(note: Int, timestampSeconds: TimeInterval)
    }

    enum Decision: Equatable, Sendable {
        case none
        case cancelPendingSend
        case scheduleSend(deadlineTimestampSeconds: TimeInterval)
        case sendNow
    }

    private(set) var phraseBuffer = DuetPhraseBuffer()
    private var phraseStartTimestampSeconds: TimeInterval?
    private var pendingSendDeadlineTimestampSeconds: TimeInterval?

    init() {}

    var hasPendingSend: Bool { pendingSendDeadlineTimestampSeconds != nil }

    mutating func handle(_ event: Event) -> Decision {
        switch event {
        case let .noteOn(note, velocity, timestampSeconds):
            phraseBuffer.recordNoteOn(midi: note, velocity: velocity, timestampSeconds: timestampSeconds)
            if phraseStartTimestampSeconds == nil {
                phraseStartTimestampSeconds = timestampSeconds
            }

            if pendingSendDeadlineTimestampSeconds != nil {
                pendingSendDeadlineTimestampSeconds = nil
                return .cancelPendingSend
            }
            return .none

        case let .noteOff(note, timestampSeconds):
            phraseBuffer.recordNoteOff(midi: note, timestampSeconds: timestampSeconds)

            guard phraseBuffer.heldNotesCount == 0 else { return .none }
            guard let phraseStartTimestampSeconds else { return .none }

            let phraseDurationSeconds = max(0, timestampSeconds - phraseStartTimestampSeconds)
            if phraseDurationSeconds > 3.0 {
                pendingSendDeadlineTimestampSeconds = nil
                self.phraseStartTimestampSeconds = nil
                return .sendNow
            }

            let deadline = timestampSeconds + 0.6
            pendingSendDeadlineTimestampSeconds = deadline
            return .scheduleSend(deadlineTimestampSeconds: deadline)
        }
    }

    mutating func flushPhraseIfAny(endTimestampSeconds: TimeInterval) -> [ImprovDialogueNote] {
        pendingSendDeadlineTimestampSeconds = nil
        phraseStartTimestampSeconds = nil
        return phraseBuffer.flushPhrase(endTimestampSeconds: endTimestampSeconds).trimmedNotes
    }

    mutating func flushPhrase(endTimestampSeconds: TimeInterval) -> DuetPhraseBuffer.FlushResult {
        pendingSendDeadlineTimestampSeconds = nil
        phraseStartTimestampSeconds = nil
        return phraseBuffer.flushPhrase(endTimestampSeconds: endTimestampSeconds)
    }

    mutating func reset() {
        phraseBuffer.reset()
        phraseStartTimestampSeconds = nil
        pendingSendDeadlineTimestampSeconds = nil
    }
}
