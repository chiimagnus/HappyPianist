import SwiftUI

struct PianoTypePickerView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 32) {
            Text("选择钢琴类型")
                .font(.largeTitle.weight(.bold))

            HStack(spacing: 24) {
                ForEach(router.pianoModes.indices, id: \.self) { index in
                    let mode = router.pianoModes[index]
                    typeCard(mode: mode)
                }
            }
        }
        .padding(40)
        .frame(minWidth: 760, idealWidth: 860)
    }

    private func typeCard(mode: any PianoModeProtocol) -> some View {
        Button {
            router.selectPianoMode(mode)
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
            .frame(width: 220, height: 200)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}
