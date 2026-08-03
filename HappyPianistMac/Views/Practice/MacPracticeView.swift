import Foundation
import Notation
import Observation
import Practice
import SwiftUI

struct MacPracticeView: View {
    let songID: UUID
    @Bindable var viewModel: MacPracticeViewModel
    let onExit: @MainActor () async -> Void
    @State private var isSettingsPresented = false
    @State private var isTakeLibraryPresented = false

    init(
        songID: UUID,
        viewModel: MacPracticeViewModel,
        onExit: @escaping @MainActor () async -> Void
    ) {
        self.songID = songID
        self.viewModel = viewModel
        self.onExit = onExit
    }

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
            Button("练习设置", systemImage: "slider.horizontal.3") {
                isSettingsPresented = true
            }
            .disabled(viewModel.preparedPractice == nil)

            Button("录制库", systemImage: "music.note.list") {
                isTakeLibraryPresented = true
            }
            .disabled(viewModel.preparedPractice == nil)

            Button("返回曲库") {
                Task { await returnToLibrary() }
            }
        }
        .task(id: songID) {
            await viewModel.load(songID: songID)
        }
        .sheet(isPresented: $isSettingsPresented) {
            if let prepared = viewModel.preparedPractice {
                MacPracticeSettingsView(
                    roundConfigurationController: viewModel.roundConfigurationController,
                    measureSpans: prepared.measureSpans,
                    onApply: { await viewModel.applyPendingRoundConfiguration() }
                )
            }
        }
        .sheet(isPresented: $isTakeLibraryPresented) {
            MacTakeLibraryView(
                takeLibraryViewModel: viewModel.takeLibraryViewModel,
                takePlaybackViewModel: viewModel.takePlaybackViewModel,
                isRecording: viewModel.isRecordingTake,
                canPlayTakes: viewModel.canPlayTakes,
                errorMessage: viewModel.errorMessage ?? viewModel.takeLibraryViewModel.errorMessage,
                dismissError: viewModel.dismissError,
                playOrPause: { take in await viewModel.playOrPauseTake(take) },
                togglePlayback: { await viewModel.toggleCurrentTakePlayback() },
                stopPlayback: { await viewModel.stopTakePlayback() },
                seek: { seconds in await viewModel.seekTakePlayback(to: seconds) },
                rename: { take, name in viewModel.renameTake(take, to: name) },
                delete: { take in await viewModel.deleteTake(take) },
                clearAll: { await viewModel.clearAllTakes() },
                makeMIDIExport: viewModel.makeMIDIExport
            )
        }
    }

    private var practiceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let prepared = viewModel.preparedPractice {
                GrandStaffNotationView(
                    projection: prepared.notationProjection,
                    measureSpans: prepared.measureSpans,
                    context: GrandStaffNotationContext(),
                    scrollTickProvider: {
                        let lastStepIndex = prepared.steps.index(before: prepared.steps.endIndex)
                        let stepIndex = prepared.steps.indices.contains(viewModel.currentStepIndex)
                            ? viewModel.currentStepIndex
                            : lastStepIndex
                        return Double(prepared.steps[stepIndex].tick)
                    }
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

            if let decision = viewModel.currentCoachingDecision {
                MacPracticeCoachingCard(
                    decision: decision,
                    apply: { _ = await viewModel.applyCurrentCoachingAction() },
                    skip: { await viewModel.skipCurrentCoachingAction() }
                )
            }

            if viewModel.canReplayActiveRange {
                Button("回放所选范围", systemImage: "play.rectangle") {
                    Task { await viewModel.replayActiveRange() }
                }
                .buttonStyle(.bordered)
            }

            if viewModel.state == .guiding {
                Button(
                    viewModel.isRecordingTake ? "停止录制" : "开始录制",
                    systemImage: viewModel.isRecordingTake ? "stop.circle" : "record.circle"
                ) {
                    Task {
                        if viewModel.isRecordingTake {
                            _ = await viewModel.stopTakeRecording()
                        } else {
                            await viewModel.startTakeRecording()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.canToggleTakeRecording == false)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("练习错误")
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
        await onExit()
    }

    private func returnAfterSaving() async {
        await onExit()
    }
}

private struct MacPracticeCoachingCard: View {
    let decision: CoachingDecision
    let apply: @MainActor () async -> Void
    let skip: @MainActor () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("可复测练习建议")
                .font(.headline)
            Text("聚焦 (actionTitle)，重复 (decision.action.repeatCount.formatted()) 次。")
            Text(completionText)
                .foregroundStyle(.secondary)
            HStack {
                Button("按建议重新练习") {
                    Task { await apply() }
                }
                .buttonStyle(.borderedProminent)

                Button("暂不采用") {
                    Task { await skip() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.quaternary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var actionTitle: String {
        switch decision.action.kind {
        case .pitchAccuracy: "音高准确性"
        case .onsetAlignment: "起音对齐"
        case .chordSynchronization: "和弦同步"
        case .durationControl: "时值控制"
        case .articulationControl: "触键连贯性"
        case .voiceBalance: "声部平衡"
        case .dynamicShaping: "力度塑形"
        case .pedalCoordination: "踏板配合"
        case .tempoStability: "速度稳定性"
        case .phraseContinuity: "乐句连贯性"
        case .evidenceCheck: "输入证据"
        }
    }

    private var completionText: String {
        switch decision.action.completionCondition.target {
        case let .dimensionOutcome(_, outcome):
            let expectation = switch outcome {
            case .correct: "达到正确"
            case .incorrect: "仍需继续调整"
            case .unknown: "获得可判定结果"
            case .insufficientEvidence: "补足判定证据"
            }
            return "完成条件：再次演奏该范围后，此维度" + expectation + "。"
        case .evidenceAvailable:
            return "完成条件：再次演奏该范围后，获得足够的输入证据。"
        }
    }
}
