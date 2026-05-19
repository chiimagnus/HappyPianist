import SwiftUI

struct VirtualPianoPreparationView: View {
    @Environment(WindowCoordinator.self) private var coordinator
    @Environment(\.preparationNavigationActions) private var navigationActions
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回钢琴类型选择") {
                    navigationActions.backToTypePicker()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("虚拟钢琴准备")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button("下一步：去选曲") {
                    navigationActions.nextToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedToLibrary)
            }

            Text("放置虚拟钢琴到空间中")
                .font(.title3)
                .foregroundStyle(.secondary)

            if viewModel.isVirtualPianoPlaced {
                Label("虚拟钢琴已放置", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 700)
        .task {
            if viewModel.isVirtualPianoEnabled == false {
                let flowCoordinator = PracticeFlowCoordinator.live(
                    openImmersiveSpace: openImmersiveSpace,
                    dismissImmersiveSpace: dismissImmersiveSpace
                )
                await flowCoordinator.enterVirtualPianoPlacement(viewModel: viewModel)
            }
        }
        .onChange(of: viewModel.isVirtualPianoPlaced) {
            coordinator.flowState.isVirtualPianoPlaced = viewModel.isVirtualPianoPlaced
        }
    }

    private var canProceedToLibrary: Bool {
        coordinator.pianoModeRegistry
            .mode(for: coordinator.flowState.selectedPianoModeID)?
            .canProceedToLibrary(flowState: coordinator.flowState) ?? false
    }
}
