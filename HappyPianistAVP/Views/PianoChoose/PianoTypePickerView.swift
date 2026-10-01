import SwiftUI

struct PianoTypePickerView: View {
    @Environment(PianoSetupCoordinator.self) private var pianoSetupCoordinator

    var body: some View {
        VStack(spacing: 32) {
            Text("选择钢琴类型")
                .font(.largeTitle)
                .bold()

            HStack(spacing: 24) {
                let modes = pianoSetupCoordinator.modes
                ForEach(modes.indices, id: \.self) { index in
                    let mode = modes[index]
                    typeCard(mode: mode)
                }
            }
        }
        .padding(32)
    }

    private func typeCard(mode: any PianoModeProtocol) -> some View {
        Button {
            pianoSetupCoordinator.practiceSetupState.selectedPianoModeID = mode.id
        } label: {
            let card = mode.pickerCard
            VStack(spacing: 16) {
                Image(systemName: card.iconSystemName)
                    .font(.largeTitle)

                Text(card.title)
                    .font(.title2.weight(.semibold))

                Text(card.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, height: 220)
        }
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}

#Preview("Piano Type Picker") {
    let pianoModeRegistry: PianoModeRegistryProtocol = PianoModeRegistryService(modes: [])
    let practiceSetupState = PracticeSetupState()
    let pianoSetupCoordinator = PianoSetupCoordinator(
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: pianoModeRegistry,
        storedTouchCalibration: { nil }
    )

    return PianoTypePickerView()
        .environment(pianoSetupCoordinator)
}
