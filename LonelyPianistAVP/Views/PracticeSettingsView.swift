import SwiftUI

struct PracticeSettingsView: View {
    @AppStorage("practiceAudioRecognitionDebugOverlayEnabled") private var practiceAudioRecognitionDebugOverlayEnabled =
        false
    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("调试：显示音频识别 overlay", isOn: $practiceAudioRecognitionDebugOverlayEnabled)
            Toggle("调试：显示键盘坐标轴（X/Y/Z）", isOn: $debugKeyboardAxesOverlayEnabled)
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}

#Preview("练习设置") {
    PracticeSettingsView()
}
