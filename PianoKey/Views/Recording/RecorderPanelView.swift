import Observation
import SwiftUI

struct RecorderPanelView: View {
    @Bindable var viewModel: PianoKeyViewModel

    var body: some View {
        VStack(spacing: 0) {
            RecorderTransportBarView(viewModel: viewModel)
            Divider()

            HStack(spacing: 0) {
                RecorderLibraryView(viewModel: viewModel)
                    .frame(width: 230)

                Divider()

                PianoRollView(take: viewModel.selectedTake)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            RecorderStatusBarView(viewModel: viewModel)
        }
    }
}

