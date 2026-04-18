import SwiftUI

struct ARGuideStatusSectionView: View {
    let viewModel: ARGuideViewModel

    var body: some View {
        GroupBox("状态") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.handTrackingStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.practiceStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    let appModel = AppModel()
    ARGuideStatusSectionView(viewModel: ARGuideViewModel(appModel: appModel))
        .padding()
}
