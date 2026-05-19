import SwiftUI

struct PianoTypePickerView: View {
    @Environment(WindowCoordinator.self) private var coordinator

    var body: some View {
        VStack(spacing: 32) {
            Text("选择钢琴类型")
                .font(.largeTitle.weight(.bold))

            HStack(spacing: 24) {
                let modes = coordinator.pianoModeRegistry.modes
                ForEach(modes.indices, id: \.self) { index in
                    let mode = modes[index]
                    typeCard(mode: mode)
                }
            }
        }
        .padding(32)
        // .frame(minWidth: 860, idealWidth: 860, minHeight: 420)
    }

    private func typeCard(mode: any PianoModeProtocol) -> some View {
        Button {
            coordinator.flowState.selectedPianoModeID = mode.id
        } label: {
            let card = mode.pickerCard
            VStack(spacing: 16) {
                Image(systemName: card.iconSystemName)
                    .font(.system(size: 48))

                Text(card.title)
                    .font(.title2.weight(.semibold))

                Text(card.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, height: 220)
        }
        // .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}

#Preview("Piano Type Picker") {
    let pianoModeRegistry: PianoModeRegistryProtocol = PianoModeRegistryService(modes: [])
    let flowState = FlowState()
    let coordinator = WindowCoordinator(flowState: flowState, pianoModeRegistry: pianoModeRegistry)

    return PianoTypePickerView()
        .environment(coordinator)
}
