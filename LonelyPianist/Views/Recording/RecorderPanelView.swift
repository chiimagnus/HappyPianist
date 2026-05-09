import Observation
import SwiftUI

struct RecorderPanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        VStack(spacing: 0) {
            RecorderTransportBarView(viewModel: viewModel)
            Divider()

            PianoRollView(take: viewModel.displayedTake, playheadSec: viewModel.playheadSec)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            RecorderStatusBarView(viewModel: viewModel)
        }
    }
}
