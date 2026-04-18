import SwiftUI

struct PracticeSectionView: View {
    let viewModel: ARGuideViewModel

    var body: some View {
        GroupBox("练习") {
            VStack(alignment: .leading, spacing: 12) {
                Text("按键位高亮弹奏；也可以用下方按钮推进步骤。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ControlGroup {
                    Button("跳过") { viewModel.skipStep() }
                        .hoverEffect()
                    Button("标记为正确") { viewModel.markCorrect() }
                        .hoverEffect()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    let appModel = AppModel()
    PracticeSectionView(viewModel: ARGuideViewModel(appModel: appModel))
        .padding()
}
