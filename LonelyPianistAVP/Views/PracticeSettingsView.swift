import SwiftUI

struct PracticeSettingsView: View {
    @AppStorage("practiceMusicXMLStructureEnabled") private var isMusicXMLStructureEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用结构跳转/反复", isOn: $isMusicXMLStructureEnabled)

            Text("默认关闭。开启后会在后续版本支持 repeat/ending、D.S./D.C./coda/segno 等曲式跳转。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}

#Preview("练习设置") {
    PracticeSettingsView()
}

