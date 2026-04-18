import SwiftUI

struct HomeOrnamentBar: View {
    @Bindable var viewModel: HomeViewModel

    var body: some View {
        HStack(spacing: 12) {
            ToggleImmersiveSpaceButton(viewModel: viewModel)

            Button("导入 MusicXML…") {
                viewModel.isImporterPresented = true
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.canImportScore == false)
            .hoverEffect()
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassBackgroundEffect()
    }
}

#Preview {
    let appModel = AppModel()
    HomeOrnamentBar(viewModel: HomeViewModel(appModel: appModel))
        .padding()
}
