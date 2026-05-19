import Foundation

enum PracticeFlowImmersiveOpenResult: Equatable, Sendable {
    case opened
    case userCancelled
    case error
    case unknown
}

typealias PracticeFlowOpenImmersiveSpaceHandler = @MainActor @Sendable (String) async -> PracticeFlowImmersiveOpenResult
typealias PracticeFlowDismissImmersiveSpaceHandler = @MainActor @Sendable () async -> Void

