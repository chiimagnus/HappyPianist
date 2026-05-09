import Observation
import SwiftUI

struct MainWindowView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        NavigationStack {
            RecorderPanelView(viewModel: viewModel)
                .navigationTitle("Recorder")
        }
    }
}
