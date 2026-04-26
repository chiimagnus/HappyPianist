import SwiftUI

struct PracticeSettingsView: View {
    @AppStorage("practiceMusicXMLStructureEnabled") private var isMusicXMLStructureEnabled = false
    @AppStorage("practiceMusicXMLPerformanceTimingEnabled") private var isMusicXMLPerformanceTimingEnabled = false
    @AppStorage("practiceMusicXMLWedgeEnabled") private var isMusicXMLWedgeEnabled = false
    @AppStorage("practiceMusicXMLGraceEnabled") private var isMusicXMLGraceEnabled = false
    @AppStorage("practiceMusicXMLFermataEnabled") private var isMusicXMLFermataEnabled = false
    @AppStorage("practiceMusicXMLArpeggiateEnabled") private var isMusicXMLArpeggiateEnabled = false
    @AppStorage("practiceMusicXMLWordsSemanticsEnabled") private var isMusicXMLWordsSemanticsEnabled = false
    @AppStorage("practiceAudioRecognitionEnabled") private var practiceAudioRecognitionEnabled = true
    @AppStorage("practiceAudioRecognitionDebugOverlayEnabled") private var practiceAudioRecognitionDebugOverlayEnabled = false
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("启用结构跳转/反复", isOn: $isMusicXMLStructureEnabled)

            Text("默认关闭。开启后会在后续版本支持 repeat/ending、D.S./D.C./coda/segno 等曲式跳转。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("启用 performance timing（attack/release）", isOn: $isMusicXMLPerformanceTimingEnabled)

            Text("默认关闭。仅影响自动播放的起音/释音时序，不影响 tick→秒 的 tempo 主链路。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("启用 wedge（渐强/渐弱）", isOn: $isMusicXMLWedgeEnabled)
            Toggle("启用 grace（装饰音时序）", isOn: $isMusicXMLGraceEnabled)
            Toggle("启用 fermata（延长/停顿）", isOn: $isMusicXMLFermataEnabled)
            Toggle("启用 arpeggiate（琶音起音错开）", isOn: $isMusicXMLArpeggiateEnabled)
            Toggle("启用 words 语义（rit./accel./Ped./*）", isOn: $isMusicXMLWordsSemanticsEnabled)

            Text("默认关闭。仅在自动播放时生效，用于更贴合谱面的听感与提示。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("启用 Step3 音频识别", isOn: $practiceAudioRecognitionEnabled)
            Toggle("调试：显示音频识别 overlay", isOn: $practiceAudioRecognitionDebugOverlayEnabled)

            Divider()

            Toggle("调试：显示键盘坐标轴（X/Y/Z）", isOn: $debugKeyboardAxesOverlayEnabled)
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}

#Preview("练习设置") {
    PracticeSettingsView()
}
