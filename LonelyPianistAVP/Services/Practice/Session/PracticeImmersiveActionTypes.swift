import Foundation

enum PracticeImmersiveOpenResult: Equatable, Sendable {
    case opened
    case userCancelled
    case error
    case unknown
}

typealias PracticeImmersiveOpenHandler = @MainActor @Sendable (String) async -> PracticeImmersiveOpenResult
typealias PracticeImmersiveDismissHandler = @MainActor @Sendable () async -> Void

