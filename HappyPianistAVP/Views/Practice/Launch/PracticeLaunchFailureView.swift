import SwiftUI

struct PracticeLaunchFailureView: View {
    let failure: PracticeLaunchFailure
    let onRetry: @MainActor () -> Void
    let canRecoverCorruptedProgress: Bool
    let onRecoverCorruptedProgress: @MainActor () -> Void
    let onReturn: @MainActor () -> Void
    @State private var isRecoveryConfirmationPresented = false

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
                    if canRecoverCorruptedProgress {
                        Button("备份并重置记录", systemImage: "externaldrive.badge.exclamationmark") {
                            isRecoveryConfirmationPresented = true
                        }
                    }
                    Button("返回选曲库", systemImage: "chevron.backward", action: onReturn)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding()
        }
        .scrollIndicators(.hidden)
        .confirmationDialog(
            "备份并重置练习记录？",
            isPresented: $isRecoveryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("备份并重置", role: .destructive) {
                onRecoverCorruptedProgress()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("损坏的原文件会先保留为本地备份，然后创建新的空练习记录。曲谱文件不会受影响。")
        }
    }
}

struct PracticeProgressAccessFailureBanner: View {
    let failure: PracticeLaunchFailure
    let onRetry: @MainActor () -> Void
    let onRecoverCorruptedProgress: @MainActor () -> Void
    @State private var isRecoveryConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(failure.title, systemImage: "exclamationmark.triangle")
                .font(.headline)
                .bold()
            Text("曲谱与设置仍可查看；恢复记录前不能开始练习。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("重试", systemImage: "arrow.clockwise", action: onRetry)
                    .buttonStyle(.borderedProminent)
                if failure.recoveryAction == .backupAndResetCorruptedProgress {
                    Button("备份并重置记录", systemImage: "externaldrive.badge.exclamationmark") {
                        isRecoveryConfirmationPresented = true
                    }
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding()
        .glassBackgroundEffect()
        .confirmationDialog(
            "备份并重置练习记录？",
            isPresented: $isRecoveryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("备份并重置", role: .destructive, action: onRecoverCorruptedProgress)
            Button("取消", role: .cancel) {}
        } message: {
            Text("损坏的原文件会先保留为本地备份，然后创建新的空练习记录。曲谱文件不会受影响。")
        }
    }
}
