import SwiftUI

struct ToggleImmersiveSpaceButton: View {

    @Bindable var viewModel: HomeViewModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        Button {
            Task { @MainActor in
                switch viewModel.immersiveSpaceState {
                    case .open:
                        viewModel.setImmersiveSpaceState(.inTransition)
                        await dismissImmersiveSpace()
                        // Don't set immersiveSpaceState to .closed because there
                        // are multiple paths to ImmersiveView.onDisappear().
                        // Only set .closed in ImmersiveView.onDisappear().

                    case .closed:
                        viewModel.setImmersiveSpaceState(.inTransition)
                        viewModel.beginNewARGuideSession()
                        switch await openImmersiveSpace(id: viewModel.immersiveSpaceID) {
                            case .opened:
                                // Don't set immersiveSpaceState to .open because there
                                // may be multiple paths to ImmersiveView.onAppear().
                                // Only set .open in ImmersiveView.onAppear().
                                break

                            case .userCancelled, .error:
                                // On error, we need to mark the immersive space
                                // as closed because it failed to open.
                                fallthrough
                            @unknown default:
                                // On unknown response, assume space did not open.
                                viewModel.setImmersiveSpaceState(.closed)
                        }

                    case .inTransition:
                        // This case should not ever happen because button is disabled for this case.
                        break
                }
            }
        } label: {
            Label(
                viewModel.immersiveSpaceState == .open ? "结束 AR 引导" : "开始 AR 引导",
                systemImage: viewModel.immersiveSpaceState == .open ? "stop.fill" : "play.fill"
            )
        }
        .disabled(viewModel.immersiveSpaceState == .inTransition)
        .animation(.none, value: 0)
        .buttonStyle(.borderedProminent)
        .tint(viewModel.immersiveSpaceState == .open ? .red : .accentColor)
        .bold()
        .hoverEffect()
    }
}
