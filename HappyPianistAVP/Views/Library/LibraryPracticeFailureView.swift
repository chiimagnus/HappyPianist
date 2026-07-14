import SwiftUI

struct LibraryPracticeFailureView: View {
    let failure: PracticeLaunchFailure
    let wasRecordedInDiagnostics: Bool
    let onRetry: () -> Void
    let onImportMusicXML: () -> Void

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
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if wasRecordedInDiagnostics {
                    Label("此错误已写入诊断日志", systemImage: "doc.text.magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button("重新准备", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.borderedProminent)

                    Button("导入其他曲谱", systemImage: "square.and.arrow.down", action: onImportMusicXML)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
