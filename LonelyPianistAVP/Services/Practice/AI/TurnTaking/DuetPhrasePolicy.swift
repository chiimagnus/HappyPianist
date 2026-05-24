import Foundation
import ImprovProtocol

/// Implements A.I. Duet-equivalent trimming and reply-length policy (`AI.js`).
///
/// Note: phrase trimming itself lives in `DuetPhraseBuffer.flushPhrase(...)`.
struct DuetPhrasePolicy: Sendable {
    struct Result: Equatable, Sendable {
        let promptNotes: [ImprovDialogueNote]
        let promptEndTimeSeconds: TimeInterval
        let desiredReplySeconds: TimeInterval
        let desiredTotalDurationSeconds: TimeInterval
    }

    static func makeResult(from flushedPhrase: DuetPhraseBuffer.FlushResult) -> Result {
        let endTimeSeconds = flushedPhrase.endTimeSeconds
        let additional = clamp(endTimeSeconds, min: 1, max: 8)
        return Result(
            promptNotes: flushedPhrase.trimmedNotes,
            promptEndTimeSeconds: endTimeSeconds,
            desiredReplySeconds: additional,
            desiredTotalDurationSeconds: endTimeSeconds + additional
        )
    }

    private static func clamp(_ value: TimeInterval, min: TimeInterval, max: TimeInterval) -> TimeInterval {
        Swift.min(Swift.max(value, min), max)
    }
}
