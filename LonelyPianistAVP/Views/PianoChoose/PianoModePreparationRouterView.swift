import SwiftUI

struct PianoModePreparationRouterView: View {
    let route: PianoModePreparationRoute
    @Bindable var arGuideViewModel: ARGuideViewModel

    init(route: PianoModePreparationRoute, arGuideViewModel: ARGuideViewModel) {
        self.route = route
        _arGuideViewModel = Bindable(wrappedValue: arGuideViewModel)
    }

    var body: some View {
        switch route {
        case .realPiano:
            RealPianoPreparationView(viewModel: arGuideViewModel)
        case .bluetoothMIDI:
            BluetoothMIDIPreparationView(viewModel: arGuideViewModel)
        case .virtualPiano:
            VirtualPianoPreparationView(viewModel: arGuideViewModel)
        }
    }
}
