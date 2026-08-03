import Foundation
import Notation
import Observation
import Practice
import SwiftUI

struct MacPracticeView: View {
    let songID: UUID
    @Bindable var viewModel: MacPracticeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .preparing:
                ProgressView("正在准备练习")
            case .guiding, .completed:
                practiceContent
            case .inputUnavailable:
                unavailableContent(
                    title: "需要 MIDI 输入",
                    retryTitle: "重新检查设备",
                    retry: viewModel.retryPreparation
                )
            case .preparationFailed:
                unavailableContent(
                    title: "无法准备曲谱",
                    retryTitle: "重新尝试",
                    retry: viewModel.retryPreparation
                )
            case .progressRecoveryRequired:
                unavailableContent(
                    title: "练习进度需要恢复",
                    retryTitle: "恢复进度",
                    retry: viewModel.recoverProgress
                )
            case .saveFailed:
                unavailableContent(
                    title: "进度尚未保存",
                    retryTitle: "重试保存并返回",
                    retry: returnAfterSaving
                )
            }
        }
        .navigationTitle("MIDI 练习")
        .toolbar {
            Button("返回曲库") {
                Task { await returnToLibrary() }
            }
        }
        .task(id: songID) {
            await viewModel.load(songID: songID)
        }
        .onDisappear {
            Task {
                _ = await viewModel.returnToLibrary()
            }
        }
    }

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let prepared = viewModel.preparedPractice {
                GrandStaffNotationView(
                    projection: prepared.notationProjection,
                    measureSpans: prepared.measureSpans,
                    context: GrandStaffNotationContext(),
                    scrollTickProvider: { Double(prepared.steps[viewModel.currentStepIndex].tick) }
                )
                .containerRelativeFrame(.vertical, count: 3, span: 2, spacing: 16)

                Text(stepDescription(for: prepared))
                    .font(.headline)
                    .accessibilityLabel("当前练习步骤")
                    .accessibilityValue(stepDescription(for: prepared))
            }

            switch viewModel.state {
            case .guiding:
                Text("正在等待所选 MIDI 输入。未选择或断开的输出不会影响输入判定；当前没有可用输出时不提供回放。")
                    .foregroundStyle(.secondary)
            case .completed:
                ContentUnavailableView(
                    "本轮完成",
                    systemImage: "checkmark.circle",
                    description: Text("已保留批准的小节练习事实。返回曲库前会安全保存。")
                )
            default:
                EmptyView()
            }

            if let lastAttempt = viewModel.lastAttempt {
                Text(attemptDescription(lastAttempt))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("最近一次判定")
            }

            if viewModel.canPlayCurrentStepReference {
                Button("播放当前步骤", systemImage: "speaker.wave.2") {
                    Task { await viewModel.playCurrentStepReference() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private func unavailableContent(
        title: String,
        retryTitle: String,
        retry: @escaping @MainActor () async -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "pianokeys")
        } description: {
            Text(viewModel.errorMessage ?? "请处理后重试。")
        } actions: {
            Button(retryTitle) {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func stepDescription(for prepared: PreparedPractice) -> String {
        let completedCount = min(viewModel.currentStepIndex, prepared.steps.count)
        return "第 \(completedCount.formatted()) / \(prepared.steps.count.formatted()) 步"
    }

    private func attemptDescription(_ attempt: StepAttemptMatchResult) -> String {
        switch attempt {
        case .matched:
            "判定：匹配"
        case .wrongNote:
            "判定：音高不匹配"
        case .missingNotes:
            "判定：缺少音符"
        case .incompleteChord:
            "判定：和弦未完整弹奏"
        case .insufficientEvidence:
            "判定：证据不足，未记为错误"
        }
    }

    private func returnToLibrary() async {
        guard await viewModel.returnToLibrary() else { return }
        dismiss()
    }

    private func returnAfterSaving() async {
        guard await viewModel.retrySavingAndReturn() else { return }
        dismiss()
    }
}
