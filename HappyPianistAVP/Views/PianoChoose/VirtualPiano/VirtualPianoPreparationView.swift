import SwiftUI

struct VirtualPianoPreparationView: View {
    @Environment(PianoSetupCoordinator.self) private var pianoSetupCoordinator
    @Environment(\.preparationNavigationActions) private var navigationActions
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回钢琴类型选择") {
                    viewModel.setPracticeVirtualPianoEnabled(false)
                    navigationActions.backToTypePicker()
                }

                Spacer()

                Text("虚拟钢琴准备")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button("完成设置") {
                    viewModel.hideVirtualPiano()
                    navigationActions.finishSetup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!pianoSetupCoordinator.isSetupReady)
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
            pianoSetupCoordinator.practiceSetupState.isVirtualPianoPlaced = viewModel.isVirtualPianoPlaced
        }
        .onDisappear {
            viewModel.hideVirtualPiano()
        }
    }
}
