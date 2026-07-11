import SwiftUI

struct PracticePassageSetupView: View {
    @Bindable var roundConfigurationController: PracticeRoundConfigurationController
    let measureSpans: [MusicXMLMeasureSpan]
    let onCancel: () -> Void
    let onStart: () -> Void

    @State private var startIndex = 0
    @State private var endIndex = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("练习片段") {
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

                Section("本轮规则") {
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
            .navigationTitle("选择练习片段")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始练习", action: onStart)
                        .disabled(measureSpans.isEmpty)
                }
            }
            .onAppear(perform: synchronizeSelection)
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
        .frame(minWidth: 520, minHeight: 520)
    }

    private func synchronizeSelection() {
        guard measureSpans.isEmpty == false else { return }
        if let passage = roundConfigurationController.pendingPassage {
            startIndex = measureSpans.firstIndex(where: { $0.occurrenceID == passage.start }) ?? 0
            endIndex = measureSpans.firstIndex(where: { $0.occurrenceID == passage.end }) ?? startIndex
        } else {
            startIndex = 0
            endIndex = measureSpans.count - 1
        }
        updatePendingPassage()
    }

    private func updatePendingPassage() {
        guard measureSpans.indices.contains(startIndex),
              measureSpans.indices.contains(endIndex),
              let passage = PracticePassage(
                  start: measureSpans[startIndex].occurrenceID,
                  end: measureSpans[endIndex].occurrenceID
              )
        else { return }
        roundConfigurationController.pendingPassage = passage
    }

    private func measureTitle(at index: Int) -> String {
        let span = measureSpans[index]
        return span.sourceMeasureNumberToken.map { "第 \($0) 小节" } ?? "第 \(index + 1) 小节"
    }
}
