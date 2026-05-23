import SwiftUI

struct AudioOutputVolumeRow: View {
    @AppStorage(AudioOutputVolumeSettings.userDefaultsKey)
    private var audioOutputVolume = Double(AudioOutputVolumeSettings.defaultValue)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("输出音量（AVP）")
            HStack {
                Slider(value: $audioOutputVolume, in: 0 ... 1)
                Text(audioOutputVolume, format: .percent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            Text("调到 0 可避免与真实钢琴叠音。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
