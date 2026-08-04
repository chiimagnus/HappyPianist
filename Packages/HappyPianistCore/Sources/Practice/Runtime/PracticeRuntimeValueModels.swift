import Foundation

public enum PracticeSessionState: Equatable, Sendable {
    case idle
    case ready
    case guiding(stepIndex: Int)
    case completed
}

public enum StepAttemptMatchResult: Equatable, Sendable {
    case matched
    case wrongNote
    case missingNotes
    case incompleteChord
    case insufficientEvidence

    public var isMatched: Bool { self == .matched }
}

public enum PracticeEvidenceOutcome: String, Codable, Equatable, Hashable, Sendable {
    case correct
    case incorrect
    case unknown
    case insufficientEvidence
}
