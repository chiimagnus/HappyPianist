import SwiftUI

struct HomeStatusSectionView: View {
    let viewModel: HomeViewModel

    var body: some View {
        GroupBox("状态") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("AR 引导") {
                    Text(viewModel.immersiveStatusText)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("校准") {
                    Text(viewModel.calibrationStatusText)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("谱子") {
                    Text(viewModel.scoreStatusText)
                        .foregroundStyle(.secondary)
                }

                if let stepCountText = viewModel.stepCountText {
                    LabeledContent("步骤") {
                        Text(stepCountText)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(viewModel.nextActionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = viewModel.calibrationStatusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    let appModel = AppModel()
    HomeStatusSectionView(viewModel: HomeViewModel(appModel: appModel))
        .padding()
}
