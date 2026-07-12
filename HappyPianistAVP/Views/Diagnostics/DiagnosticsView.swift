import SwiftUI

struct DiagnosticsView: View {
    @Bindable var viewModel: DiagnosticsViewModel
    @State private var isExportPresented = false
    @State private var isClearConfirmationPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("诊断日志") {
                    LabeledContent("保留时间", value: "7 天")
                    LabeledContent("事件数量", value: viewModel.summary.eventCount.formatted())
                    LabeledContent("日志大小", value: formattedByteCount)
                    LabeledContent("覆盖范围", value: coverageText)
                }

                Section {
                    Button("导出诊断日志", systemImage: "square.and.arrow.up") {
                        Task { @MainActor in
                            if await viewModel.prepareExport() {
                                isExportPresented = true
                            }
                        }
                    }
                    .disabled(viewModel.isExporting)

                    Button("清除诊断日志", systemImage: "trash", role: .destructive) {
                        isClearConfirmationPresented = true
                    }
                    .disabled(viewModel.summary.eventCount == 0)
                } footer: {
                    Text("导出包不包含曲谱、音频、逐音 MIDI、AI 对话、密钥或本机绝对路径。")
                }
            }
            .navigationTitle("诊断")
            .overlay {
                if viewModel.isLoading || viewModel.isExporting {
                    ProgressView(viewModel.isExporting ? "正在生成诊断包…" : "正在读取诊断日志…")
                        .padding()
                        .glassBackgroundEffect()
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .task {
            await viewModel.reload()
        }
        .fileExporter(
            isPresented: $isExportPresented,
            document: viewModel.pendingArchive.map { DiagnosticsArchiveDocument(data: $0.data) },
            contentType: .zip,
            defaultFilename: viewModel.pendingArchive?.fileName ?? "HappyPianist-Diagnostics.zip"
        ) { _ in
            viewModel.finishExport()
        }
        .confirmationDialog(
            "清除最近 7 天的诊断日志？",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task { await viewModel.clearLogs() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只删除可导出的诊断日志，不会删除曲谱、录音或练习进度。")
        }
        .alert(
            "诊断错误",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.dismissError()
                    }
                }
            )
        ) {
            Button("好", action: viewModel.dismissError)
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
    }

    private var formattedByteCount: String {
        ByteCountFormatStyle(style: .file).format(viewModel.summary.totalBytes)
    }

    private var coverageText: String {
        guard let start = viewModel.summary.coverageStart,
              let end = viewModel.summary.coverageEnd
        else {
            return "暂无日志"
        }
        return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
    }
}
