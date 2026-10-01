import SwiftUI

@MainActor
func makeImmersiveSpaceOpenHandler(
    _ openImmersiveSpace: OpenImmersiveSpaceAction
) -> ImmersiveSpaceOpenHandler {
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
func makeImmersiveSpaceDismissHandler(
    _ dismissImmersiveSpace: DismissImmersiveSpaceAction
) -> ImmersiveSpaceDismissHandler {
    {
        await dismissImmersiveSpace()
    }
}
