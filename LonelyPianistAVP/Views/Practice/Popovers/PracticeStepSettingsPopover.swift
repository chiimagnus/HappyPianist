import SwiftUI

struct PracticeStepSettingsPopover: View {
    @Binding var virtualPerformerEnabled: Bool
    let backendStatusText: String?
    let lastImprovStatusText: String?
    let recordingSourceText: String?
    let isAIPerformanceActive: Bool
    let isVirtualPianoMode: Bool
    let gazePlaneDiskStatusText: String?
    let onOpenTakeLibrary: () -> Void
    let onRetryVirtualPianoPlacement: () -> Void
    let onDebugTriggerAIPerformance: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PracticeSettingsView(
                virtualPerformerEnabled: $virtualPerformerEnabled,
                backendStatusText: backendStatusText,
                lastImprovStatusText: lastImprovStatusText,
                recordingSourceText: recordingSourceText,
                onOpenTakeLibrary: onOpenTakeLibrary
            )
            .disabled(isAIPerformanceActive)

            #if DEBUG && targetEnvironment(simulator)
            if virtualPerformerEnabled, let onDebugTriggerAIPerformance {
                Divider()
                Button("调试：触发 AI 演奏", systemImage: "play.fill") {
                    onDebugTriggerAIPerformance()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(isAIPerformanceActive)
            }
            #endif

            if isVirtualPianoMode {
                Divider()
                    .padding(.horizontal, 16)

                if let status = gazePlaneDiskStatusText {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                Button("重试放置", systemImage: "arrow.clockwise") {
                    onRetryVirtualPianoPlacement()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(isAIPerformanceActive)
                .padding(.horizontal, 16)
            }
        }
        .frame(minWidth: 320)
    }
}
