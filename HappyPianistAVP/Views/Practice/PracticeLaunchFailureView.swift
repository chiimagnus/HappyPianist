import SwiftUI

struct PracticeLaunchFailureView: View {
    let failure: PracticeLaunchFailure
    let onRetry: @MainActor () -> Void
    let onReturn: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(failure.title, systemImage: "exclamationmark.triangle")
                    .font(.title3)
                    .bold()

                Text(failure.explanation)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("技术详情")
                        .font(.headline)
                    Text(failure.technicalDetails)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack {
                    Button("重试", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.borderedProminent)
                    Button("返回选曲库", systemImage: "chevron.backward", action: onReturn)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
        }
        .scrollIndicators(.hidden)
    }
}
