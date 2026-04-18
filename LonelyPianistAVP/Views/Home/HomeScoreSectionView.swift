import SwiftUI

struct HomeScoreSectionView: View {
    let viewModel: HomeViewModel

    var body: some View {
        GroupBox("谱子") {
            VStack(alignment: .leading, spacing: 10) {
                Text("导入 MusicXML 后会生成练习步骤。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let importErrorMessage = viewModel.importErrorMessage {
                    Text(importErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("导入 MusicXML…") {
                    viewModel.isImporterPresented = true
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.canImportScore == false)
                .hoverEffect()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    let appModel = AppModel()
    HomeScoreSectionView(viewModel: HomeViewModel(appModel: appModel))
        .padding()
}
