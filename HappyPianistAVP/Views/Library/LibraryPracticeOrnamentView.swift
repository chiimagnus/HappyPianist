import SwiftUI

struct LibraryPracticeOrnamentView: View {
    @Bindable var viewModel: SongLibraryViewModel
    let isStartEnabled: Bool
    let onStartPractice: () -> Void
    let onImportMusicXML: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch viewModel.practicePreparationState {
                case .idle:
                    ContentUnavailableView(
                        "选择一首曲目",
                        systemImage: "music.note.list",
                        description: Text("练习信息和设置会显示在这里。")
                    )
                case .loading:
                    ScrollView {
                        LibraryPracticeSkeletonView()
                            .padding(20)
                    }
                    .scrollIndicators(.hidden)
                case let .failure(failure):
                    LibraryPracticeFailureView(
                        failure: failure,
                        wasRecordedInDiagnostics: viewModel.wasSelectedPreparationFailureRecorded,
                        onRetry: viewModel.retrySelectedPracticePreparation,
                        onImportMusicXML: onImportMusicXML
                    )
                    .padding(20)
                case let .ready(_, identity):
                    if let controller = viewModel.preparedRoundConfigurationController,
                       let presentation = viewModel.selectedPracticePresentation
                    {
                        LibraryPracticeReadyView(
                            roundConfigurationController: controller,
                            measureSpans: viewModel.preparedMeasureSpans,
                            presentation: presentation
                        )
                        .id(identity)
                    } else {
                        ScrollView {
                            LibraryPracticeSkeletonView()
                                .padding(20)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let summary = viewModel.selectedPracticePresentation?.launchSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button("去练习！", systemImage: "music.note", action: onStartPractice)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .frame(maxWidth: .infinity)
                    .disabled(isStartEnabled == false)
            }
            .padding(20)
        }
        .frame(width: 400)
    }
}

private struct LibraryPracticeReadyView: View {
    @Bindable var roundConfigurationController: PracticeRoundConfigurationController
    let measureSpans: [MusicXMLMeasureSpan]
    let presentation: LibraryPracticePanelPresentation

    @State private var startIndex = 0
    @State private var endIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                practiceOverview
                Divider()
                passageSettings
                Divider()
                roundSettings
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: synchronizePassageSelection)
        .onChange(of: roundConfigurationController.pendingPassage) {
            synchronizePassageSelection()
        }
        .onChange(of: startIndex) {
            if endIndex < startIndex {
                endIndex = startIndex
            }
            updatePendingPassage()
        }
        .onChange(of: endIndex) {
            updatePendingPassage()
        }
    }

    private var practiceOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("练习概览")
                .font(.headline)

            LabeledContent("稳定小节") {
                Text("\(presentation.stableMeasureCount) / \(presentation.totalMeasureCount)")
                    .monospacedDigit()
            }

            Text(presentation.resumeText)
                .foregroundStyle(.secondary)

            if let hotspotTitle = presentation.hotspotTitle {
                Label("最近卡点：\(hotspotTitle)", systemImage: "scope")
                    .foregroundStyle(.secondary)
            }

            PracticeMeasureMapView(viewModel: presentation.measureMap)
        }
    }

    private var passageSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("练习片段")
                .font(.headline)

            Picker("开始小节", selection: $startIndex) {
                ForEach(measureSpans.indices, id: \.self) { index in
                    Text(measureTitle(at: index)).tag(index)
                }
            }

            Picker("结束小节", selection: $endIndex) {
                ForEach(startIndex ..< measureSpans.count, id: \.self) { index in
                    Text(measureTitle(at: index)).tag(index)
                }
            }
        }
    }

    private var roundSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本轮设置")
                .font(.headline)

            Picker("练习手", selection: $roundConfigurationController.pendingHandMode) {
                ForEach(PracticeHandMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("速度") {
                Text(
                    roundConfigurationController.pendingTempoScale,
                    format: .percent.precision(.fractionLength(0))
                )
                .monospacedDigit()
            }

            Slider(
                value: $roundConfigurationController.pendingTempoScale,
                in: PracticeRoundConfiguration.supportedTempoRange,
                step: 0.05
            )

            Toggle("循环当前片段", isOn: $roundConfigurationController.pendingLoopEnabled)

            Stepper(
                "连续成功 \(roundConfigurationController.pendingRequiredSuccesses) 次",
                value: $roundConfigurationController.pendingRequiredSuccesses,
                in: PracticeRoundConfiguration.supportedSuccessRange
            )
        }
    }

    private func synchronizePassageSelection() {
        guard measureSpans.isEmpty == false else { return }
        guard let passage = roundConfigurationController.pendingPassage else {
            startIndex = 0
            endIndex = measureSpans.count - 1
            updatePendingPassage()
            return
        }
        startIndex = measureSpans.firstIndex { $0.occurrenceID == passage.start } ?? 0
        endIndex = measureSpans.firstIndex { $0.occurrenceID == passage.end } ?? startIndex
    }

    private func updatePendingPassage() {
        guard measureSpans.indices.contains(startIndex),
              measureSpans.indices.contains(endIndex),
              let passage = PracticePassage(
                  start: measureSpans[startIndex].occurrenceID,
                  end: measureSpans[endIndex].occurrenceID
              )
        else { return }
        if roundConfigurationController.pendingPassage != passage {
            roundConfigurationController.pendingPassage = passage
        }
    }

    private func measureTitle(at index: Int) -> String {
        let span = measureSpans[index]
        let baseTitle = PracticePassagePresentation.measureTitle(span.sourceMeasureID)
        let matchingIndices = measureSpans.indices.filter {
            measureSpans[$0].sourceMeasureID == span.sourceMeasureID
        }
        guard matchingIndices.count > 1,
              let repeatedIndex = matchingIndices.firstIndex(of: index)
        else {
            return "第 \(baseTitle) 小节"
        }
        return "第 \(baseTitle) 小节 · 第 \(repeatedIndex + 1) 次"
    }
}
