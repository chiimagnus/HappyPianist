import Practice
import SwiftUI

struct LibraryScoreHistoryView: View {
    @Bindable var library: SongLibraryViewModel
    @State private var pendingResetIdentity: SongPracticeLibrarySelectionIdentity?
    @State private var isResetConfirmationPresented = false

    var body: some View {
        Group {
            switch library.practiceSnapshotState {
            case nil:
                EmptyView()
            case .loading:
                ProgressView("正在读取练习记录")
            case .invitation:
                Text("还没有练习记录。开始练习后，这里会标记已稳定、学习中和重点小节。")
            case let .overview(overview):
                VStack(alignment: .leading, spacing: 4) {
                    Text("练习 \(overview.sessionSummary.sessionCount) 次 · \(Duration.milliseconds(overview.sessionSummary.totalActiveDurationMilliseconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))\(overview.sessionSummary.streak.map { " · 连续 \($0.dayCount) 天" } ?? "")")
                    if overview.scoreRevision != library.scorePreview.prepared?.identity.scoreRevision {
                        Text("当前曲谱的进度尚待建立；不标记未练习小节。")
                    } else if case let .available(progress) = overview.measureProgress {
                        Text("已稳定 \(progress.stableSourceMeasureCount) · 学习中 \(progress.learningSourceMeasureCount) · 未练习 \(progress.unpracticedSourceMeasureCount)")
                    }
                }
            case let .unavailable(unavailable):
                HStack {
                    Text(unavailable.reason == .corrupted ? "练习记录已损坏；曲谱仍可阅读。" : "暂时无法读取练习记录；曲谱仍可阅读。")
                    Button("重试记录", systemImage: "arrow.clockwise", action: library.retrySelectedPracticeSnapshot)
                    if unavailable.recoveryOptions == .retryAndConfirmedBackupReset {
                        Button("备份并重置", systemImage: "externaldrive.badge.xmark") {
                            pendingResetIdentity = unavailable.identity
                            isResetConfirmationPresented = true
                        }
                    }
                }
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom)
        .confirmationDialog("备份并重置练习记录？", isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
            Button("备份并重置", role: .destructive) {
                guard let identity = pendingResetIdentity else { return }
                pendingResetIdentity = nil
                Task { await library.recoverCorruptedSelectedPracticeHistory(expectedIdentity: identity) }
            }
            Button("取消", role: .cancel) { pendingResetIdentity = nil }
        } message: {
            Text("原损坏文件会先备份，再创建空练习记录。此操作影响所有曲目的练习记录，不会删除曲谱。")
        }
    }
}
