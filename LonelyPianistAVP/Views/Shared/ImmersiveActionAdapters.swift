import SwiftUI

@MainActor
func makePracticeImmersiveOpenHandler(
    _ openImmersiveSpace: OpenImmersiveSpaceAction
) -> PracticeImmersiveOpenHandler {
    { id in
        switch await openImmersiveSpace(id: id) {
        case .opened:
            return .opened
        case .userCancelled:
            return .userCancelled
        case .error:
            return .error
        @unknown default:
            return .unknown
        }
    }
}

@MainActor
func makePracticeImmersiveDismissHandler(
    _ dismissImmersiveSpace: DismissImmersiveSpaceAction
) -> PracticeImmersiveDismissHandler {
    {
        await dismissImmersiveSpace()
    }
}
