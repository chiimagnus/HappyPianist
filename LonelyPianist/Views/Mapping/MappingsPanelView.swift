import Observation
import SwiftUI

struct MappingsPanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ProfileSectionView(viewModel: viewModel)
                KeyboardMapSectionView(viewModel: viewModel)
                RulesEditorSectionView(viewModel: viewModel)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
