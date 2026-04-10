import Observation
import SwiftUI

struct MappingsPanelView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    var body: some View {
        PianoMappingsEditorView(viewModel: viewModel)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
