import SwiftUI

struct VirtualPianoPreparationView: View {
    @Environment(WindowTransitionState.self) private var windowState
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
            let openHandler = makePracticeImmersiveOpenHandler(openImmersiveSpace)
            await viewModel.enterVirtualPianoPlacement(openImmersiveSpace: openHandler)
        }
        .onChange(of: viewModel.isVirtualPianoPlaced) {
            windowState.practiceSetupState.isVirtualPianoPlaced = viewModel.isVirtualPianoPlaced
        }
    }

    private var canProceedToLibrary: Bool {
        windowState.pianoModeRegistry
            .mode(for: windowState.practiceSetupState.selectedPianoModeID)?
            .canProceedToLibrary(context: PianoModeReadinessContext(practiceSetupState: windowState.practiceSetupState)) ?? false
    }
}
