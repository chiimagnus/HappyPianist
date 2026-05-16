import SwiftUI

struct PracticeStepLocalizationPopover: View {
    let practiceLocalizationStatusText: String?
    let step3ARStatusText: String
    let step3HandAssistStatusText: String
    let step3AudioStatusText: String
    let canRetryPracticeLocalization: Bool
    let shouldSuggestCalibrationStep: Bool
    let isAIPerformanceActive: Bool
    let onRetryLocalization: () -> Void
    let onRestartFromTypePicker: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(practiceLocalizationStatusText ?? "进入后会自动定位钢琴。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Text(step3ARStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(step3HandAssistStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(step3AudioStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("提示：即使定位失败或环境不支持，你也可以直接使用下方 2D 键盘的\u{201C}下一步\u{201D}继续练习。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if canRetryPracticeLocalization {
                Button("重试定位", systemImage: "arrow.clockwise") {
                    onRetryLocalization()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(isAIPerformanceActive)
            }

            if shouldSuggestCalibrationStep {
                Text("若持续失败，请回到\u{201C}钢琴类型选择\u{201D}重新开始准备。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("回到钢琴类型选择", systemImage: "house") {
                    onRestartFromTypePicker()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
            }
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}
