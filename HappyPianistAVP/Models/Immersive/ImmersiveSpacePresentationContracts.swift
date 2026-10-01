import Foundation

enum ImmersiveSpaceOpenResult: Equatable, Sendable {
    case opened
    case userCancelled
    case error
    case unknown
}

typealias ImmersiveSpaceOpenHandler =
    @MainActor @Sendable (String) async -> ImmersiveSpaceOpenResult
typealias ImmersiveSpaceDismissHandler = @MainActor @Sendable () async -> Void
