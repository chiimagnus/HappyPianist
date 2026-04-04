import Observation
import SwiftUI

struct RuntimePanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatusSectionView(viewModel: viewModel)

                RecentEventSectionView(viewModel: viewModel)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
