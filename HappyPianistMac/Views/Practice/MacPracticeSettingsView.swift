import MusicXML
import Practice
import SwiftUI

struct MacPracticeSettingsView: View {
    let roundConfigurationController: PracticeRoundConfigurationController
    let measureSpans: [MusicXMLMeasureSpan]
    let onApply: @MainActor () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var startMeasureIndex: Int
    @State private var endMeasureIndex: Int

    init(
        roundConfigurationController: PracticeRoundConfigurationController,
        measureSpans: [MusicXMLMeasureSpan],
        onApply: @escaping @MainActor () async -> Bool
    ) {
        self.roundConfigurationController = roundConfigurationController
        self.measureSpans = measureSpans
        self.onApply = onApply
        _startMeasureIndex = State(initialValue: Self.index(
            for: roundConfigurationController.pendingPassage?.start,
            in: measureSpans,
            fallback: 0
        ))
        _endMeasureIndex = State(initialValue: Self.index(
            for: roundConfigurationController.pendingPassage?.end,
            in: measureSpans,
            fallback: max(0, measureSpans.count - 1)
        ))
    }

    var body: some View {
        @Bindable var controller = roundConfigurationController

        Form {
            Section("练习范围") {
                Picker("起始小节", selection: $startMeasureIndex) {
                    ForEach(measureSpans.indices, id: \.self) { index in
                        Text(measureTitle(for: measureSpans[index])).tag(index)
                    }
                }

                Picker("结束小节", selection: $endMeasureIndex) {
                    ForEach(measureSpans.indices, id: \.self) { index in
                        Text(measureTitle(for: measureSpans[index])).tag(index)
                    }
                }
            }

            Section("本轮规则") {
                Picker("练习手", selection: $controller.pendingHandMode) {
                    ForEach(PracticeHandMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                LabeledContent("练习速度") {
                    Text(controller.pendingTempoScale, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(
                    value: $controller.pendingTempoScale,
                    in: PracticeRoundConfiguration.supportedTempoRange,
                    step: 0.05
                )

                Toggle("循环当前片段", isOn: $controller.pendingLoopEnabled)
                Stepper(
                    "连续成功 \(controller.pendingRequiredSuccesses) 次",
                    value: $controller.pendingRequiredSuccesses,
                    in: PracticeRoundConfiguration.supportedSuccessRange
                )
            }

            Section {
                Button("应用并重新开始本轮", systemImage: "arrow.clockwise") {
                    Task {
                        if await onApply() {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.hasPendingChanges == false)
            } footer: {
                Text("设置只在应用后写入进度，并从所选片段的第一步重新开始。")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 420)
        .navigationTitle("练习设置")
        .onChange(of: startMeasureIndex) {
            if endMeasureIndex < startMeasureIndex {
                endMeasureIndex = startMeasureIndex
            }
            updatePendingPassage()
        }
        .onChange(of: endMeasureIndex) {
            if endMeasureIndex < startMeasureIndex {
                startMeasureIndex = endMeasureIndex
            }
            updatePendingPassage()
        }
    }

    private func updatePendingPassage() {
        guard measureSpans.indices.contains(startMeasureIndex),
              measureSpans.indices.contains(endMeasureIndex),
              let passage = PracticePassage(
                  start: measureSpans[startMeasureIndex].occurrenceID,
                  end: measureSpans[endMeasureIndex].occurrenceID
              )
        else { return }
        roundConfigurationController.pendingPassage = passage
    }

    private func measureTitle(for span: MusicXMLMeasureSpan) -> String {
        let sourceNumber = span.sourceMeasureNumberToken ?? span.measureNumber.formatted()
        if span.occurrenceIndex == 0 {
            return "小节 \(sourceNumber)"
        }
        return "小节 \(sourceNumber)（第 \(span.occurrenceIndex + 1) 次）"
    }

    private static func index(
        for occurrenceID: PracticeMeasureOccurrenceID?,
        in measureSpans: [MusicXMLMeasureSpan],
        fallback: Int
    ) -> Int {
        guard let occurrenceID,
              let index = measureSpans.firstIndex(where: { $0.occurrenceID == occurrenceID })
        else { return fallback }
        return index
    }
}
