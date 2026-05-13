import SwiftUI

struct PianoTypePickerView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 32) {
            Text("选择钢琴类型")
                .font(.largeTitle.weight(.bold))

            HStack(spacing: 24) {
                typeCard(
                    title: "真实钢琴（音频）",
                    subtitle: "通过麦克风识别弹奏",
                    icon: "pianokeys",
                    kind: .realAudio
                )

                typeCard(
                    title: "真实钢琴（蓝牙 MIDI）",
                    subtitle: "通过系统 Bluetooth MIDI 连接",
                    icon: "dot.radiowaves.left.and.right",
                    kind: .realBluetoothMIDI
                )

                typeCard(
                    title: "虚拟钢琴",
                    subtitle: "在空间中放置虚拟钢琴",
                    icon: "arkit",
                    kind: .virtual
                )
            }
        }
        .padding(40)
        .frame(minWidth: 760, idealWidth: 860)
    }

    private func typeCard(title: String, subtitle: String, icon: String, kind: PianoKind) -> some View {
        Button {
            router.selectPianoKind(kind)
        } label: {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 48))
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, height: 200)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 20))
    }
}
