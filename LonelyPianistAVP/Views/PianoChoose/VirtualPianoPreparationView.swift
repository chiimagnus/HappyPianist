import SwiftUI

struct VirtualPianoPreparationView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("虚拟钢琴准备")
                .font(.largeTitle.weight(.bold))

            Text("放置虚拟钢琴到空间中")
                .font(.title3)
                .foregroundStyle(.secondary)

            if viewModel.isVirtualPianoPlaced {
                Label("虚拟钢琴已放置", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }

            Spacer()

            HStack {
                Button("返回钢琴类型选择") {
                    router.exitToTypePicker(reason: "user tapped back from virtual preparation")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("下一步：去选曲") {
                    router.goToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!router.canProceedToLibrary)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 700)
        .task {
            if viewModel.isVirtualPianoEnabled == false {
                await viewModel.enterVirtualPianoPlacement(
                    using: openImmersiveSpace,
                    dismissImmersiveSpace: dismissImmersiveSpace
                )
            }
        }
        .onChange(of: viewModel.isVirtualPianoPlaced) {
            router.flowState.isVirtualPianoPlaced = viewModel.isVirtualPianoPlaced
        }
    }
}
