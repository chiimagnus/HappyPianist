import Foundation

enum StepAttemptMatchResult: Equatable {
    case matched(reason: String)
    case wrong(reason: String)
    case insufficient(progress: String)
}
