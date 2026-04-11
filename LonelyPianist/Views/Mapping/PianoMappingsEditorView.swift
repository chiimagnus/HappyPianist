import AppKit
import Observation
import SwiftUI

struct PianoMappingsEditorView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @Binding var isInspectorPresented: Bool
    @State private var bindingTargetNote: Int?
    @State private var bindingMessage = "点击琴键进入绑定态；按 Esc 可取消。"
    @State private var selectedSingleNote: Int?
    @State private var selectedChordRuleID: UUID?
    @State private var chordSelectedNotes: Set<Int> = []
    @State private var chordDraftOutput: KeyStroke = KeyStroke(keyCode: 8, modifiers: [.command])
    @State private var chordOutputCaptureArmed = false
    @State private var chordMultiSelectEnabled = false

    var body: some View {
        pianoArea
            .padding(16)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                cancelBindingOnFocusLoss()
            }
            .onChange(of: viewModel.activeConfig?.id) {
                resetEditorState()
            }
            .onChange(of: chordMultiSelectEnabled) { isEnabled in
                bindingTargetNote = nil
                chordOutputCaptureArmed = false
                if isEnabled {
                    bindingMessage = "Chord 多选已开启：点击琴键可加入/移除和弦。"
                } else {
                    chordSelectedNotes.removeAll()
                    selectedChordRuleID = nil
                    bindingMessage = "Chord 多选已关闭：点击琴键将进入 Single 绑定态。"
                }
            }
            .inspector(isPresented: $isInspectorPresented) {
                inspectorPanel
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            .onChange(of: isInspectorPresented) { isPresented in
                if !isPresented {
                    bindingTargetNote = nil
                    chordOutputCaptureArmed = false
                }
            }
    }

    private var pianoArea: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                PianoKeyboardView(
                    noteRange: 48...83,
                    highlightedNotes: Set(viewModel.pressedNotes),
                    selectedNotes: selectedNotes,
                    labelsForNote: labelsForNote,
                    onTapNote: handlePianoTap
                )
                .frame(height: 220)

                Text(bindingMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Piano")
        }
        .overlay(alignment: .topLeading) {
            if let bindingTargetNote {
                bindingOverlay(note: bindingTargetNote)
                    .padding(12)
            }
        }
    }

    private var inspectorPanel: some View {
        Form {
            Section {
                Toggle("Chord Multi-Select", isOn: $chordMultiSelectEnabled)
            }

            Section("Single") {
                if let note = selectedSingleNote {
                    let rule = singleRuleByNote[note]

                    LabeledContent("Note") {
                        Text(MIDINote(note).name)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Normal") {
                        Text(rule?.output.displayLabel ?? "—")
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    LabeledContent("High Velocity") {
                        Text(highVelocityLabel(for: rule))
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    ControlGroup {
                        Button("Bind") {
                            beginBinding(note: note)
                        }

                        Button("Clear") {
                            clearSingleRule(note: note)
                        }
                        .disabled(rule == nil)
                    }
                    .controlSize(.small)
                } else {
                    Text("点击钢琴键后可绑定单键输出。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Chord") {
                if chordRules.isEmpty {
                    Text("暂无 Chord 规则")
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Rule",
                        selection: Binding(
                            get: { selectedChordRuleID },
                            set: { newValue in
                                if let id = newValue, let rule = chordRules.first(where: { $0.id == id }) {
                                    selectChordRule(rule)
                                } else {
                                    selectedChordRuleID = nil
                                }
                            }
                        )
                    ) {
                        ForEach(chordRules) { rule in
                            Text(MIDINoteParser.stringify(notes: rule.notes, separator: " "))
                                .tag(Optional(rule.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                LabeledContent("Selected") {
                    Text(MIDINoteParser.stringify(notes: chordSelectedNotes.sorted(), separator: " "))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                LabeledContent("Output") {
                    Text(chordDraftOutput.displayLabel)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                ControlGroup {
                    Button("Bind Output") {
                        startChordOutputCapture()
                    }

                    Button("Save") {
                        saveChordRule()
                    }
                    .disabled(chordSelectedNotes.isEmpty)

                    Button("Delete", role: .destructive) {
                        deleteSelectedChordRule()
                    }
                    .disabled(selectedChordRuleID == nil)
                }
                .controlSize(.small)

                if chordOutputCaptureArmed {
                    Text("等待下一次键盘输入（可带 ⌘⌥⌃⇧，Esc 取消）")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    OneShotKeyCaptureView { event in
                        handleChordOutputCapture(event)
                    }
                    .frame(width: 1, height: 1)
                }

                Text("Trigger: 严格相等（当前按下集合必须与规则集合完全一致）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Velocity") {
                Toggle(
                    "Enable Velocity",
                    isOn: Binding(
                        get: { viewModel.activeConfig?.payload.velocityEnabled ?? false },
                        set: { viewModel.setVelocityEnabled($0) }
                    )
                )

                LabeledContent("Threshold") {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.activeConfig?.payload.defaultVelocityThreshold ?? 100) },
                                set: { viewModel.setVelocityThreshold(Int($0.rounded())) }
                            ),
                            in: 1...127,
                            step: 1
                        )
                        .frame(maxWidth: 160)

                        Text("\(viewModel.activeConfig?.payload.defaultVelocityThreshold ?? 100)")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 34, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // NOTE: inspectorPanel 已收敛到 Form/Section，避免自绘分割线与卡片背景导致的非原生观感。

    private var selectedNotes: Set<Int> {
        if chordMultiSelectEnabled {
            return chordSelectedNotes
        }

        guard let selectedSingleNote else { return [] }
        return [selectedSingleNote]
    }

    private var singleRuleByNote: [Int: SingleKeyMappingRule] {
        guard let config = viewModel.activeConfig else { return [:] }
        return config.payload.singleKeyRules.reduce(into: [:]) { partialResult, rule in
            partialResult[rule.note] = rule
        }
    }

    private var singleRuleOutputByNote: [Int: String] {
        singleRuleByNote.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.output.displayLabel
        }
    }

    private var chordRules: [ChordMappingRule] {
        guard let rules = viewModel.activeConfig?.payload.chordRules else { return [] }
        return rules.sorted { lhs, rhs in
            let lhsKey = MIDINoteParser.stringify(notes: lhs.notes, separator: " ")
            let rhsKey = MIDINoteParser.stringify(notes: rhs.notes, separator: " ")
            return lhsKey < rhsKey
        }
    }

    private func labelsForNote(_ note: Int) -> PianoKeyLabels {
        PianoKeyLabels(
            noteName: MIDINote(note).name,
            mappingLabel: singleRuleOutputByNote[note]
        )
    }

    private func beginBinding(note: Int) {
        selectedSingleNote = note
        bindingTargetNote = note
        bindingMessage = "正在绑定 \(MIDINote(note).name)：请输入 1 个按键（Esc 取消）。"
    }

    private func clearSingleRule(note: Int) {
        viewModel.clearSingleKeyMapping(note: note)
        bindingMessage = "已清除 \(MIDINote(note).name) 的 Single 绑定。"
    }

    private func handlePianoTap(note: Int) {
        guard bindingTargetNote == nil, !chordOutputCaptureArmed else {
            bindingMessage = "还在编辑中，请先完成或按 Esc 取消。"
            return
        }

        if chordMultiSelectEnabled {
            toggleChordNoteSelection(note: note)
            return
        }

        beginBinding(note: note)
    }

    @ViewBuilder
    private func bindingOverlay(note: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("绑定 \(MIDINote(note).name)")
                .font(.headline)

            Text("等待下一次本地按键输入")
                .font(.caption)
                .foregroundStyle(.secondary)

            OneShotKeyCaptureView { event in
                handleCaptureEvent(event, note: note)
            }
            .frame(width: 1, height: 1)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func handleCaptureEvent(_ event: NSEvent, note: Int) {
        if isEscapeEvent(event) {
            bindingTargetNote = nil
            bindingMessage = "已取消绑定 \(MIDINote(note).name)。"
            return
        }

        if Self.modifierOnlyKeyCodes.contains(event.keyCode) {
            bindingMessage = "已忽略纯修饰键，请输入一个普通按键。"
            return
        }

        viewModel.setSingleKeyMapping(note: note, keyCode: event.keyCode)
        bindingTargetNote = nil
        let normal = KeyStroke(keyCode: event.keyCode)
        let high = normal.adding(.shift)
        bindingMessage = "已绑定 \(MIDINote(note).name)：Out=\(normal.displayLabel) / High=\(high.displayLabel)"
    }

    private func highVelocityLabel(for rule: SingleKeyMappingRule?) -> String {
        guard let rule else { return "-" }
        let high = KeyStroke(keyCode: rule.output.keyCode, modifiers: [.shift])
        return high.displayLabel
    }

    private func isEscapeEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 53 || event.characters == "\u{1B}"
    }

    private func cancelBindingOnFocusLoss() {
        guard bindingTargetNote != nil || chordOutputCaptureArmed else { return }
        let noteName = bindingTargetNote.map { MIDINote($0).name } ?? ""
        bindingTargetNote = nil
        chordOutputCaptureArmed = false
        if noteName.isEmpty {
            bindingMessage = "窗口失焦，已取消当前绑定。"
        } else {
            bindingMessage = "窗口失焦，已取消绑定 \(noteName)。"
        }
    }

    private func toggleChordNoteSelection(note: Int) {
        bindingTargetNote = nil

        if chordSelectedNotes.contains(note) {
            chordSelectedNotes.remove(note)
        } else {
            chordSelectedNotes.insert(note)
        }

        bindingMessage = "Chord 选中：\(MIDINoteParser.stringify(notes: chordSelectedNotes.sorted(), separator: " "))"
    }

    private func selectChordRule(_ rule: ChordMappingRule) {
        selectedChordRuleID = rule.id
        chordSelectedNotes = Set(rule.notes)
        chordDraftOutput = rule.output
        chordOutputCaptureArmed = false
        bindingMessage = "已选中 Chord 规则：\(MIDINoteParser.stringify(notes: rule.notes, separator: " "))"
    }

    private func saveChordRule() {
        let notes = chordSelectedNotes.sorted()
        guard !notes.isEmpty else {
            bindingMessage = "请先在键盘上选择 Chord notes。"
            return
        }

        if let selectedChordRuleID {
            viewModel.updateChordRule(
                ChordMappingRule(id: selectedChordRuleID, notes: notes, output: chordDraftOutput)
            )
            bindingMessage = "Chord 规则已更新。"
        } else {
            viewModel.createChordRule(notes: notes, output: chordDraftOutput)
            selectedChordRuleID = nil
            chordSelectedNotes.removeAll()
            bindingMessage = "Chord 规则已创建，并已清空编辑态。"
        }

        chordOutputCaptureArmed = false
    }

    private func deleteSelectedChordRule() {
        guard let selectedChordRuleID else { return }
        viewModel.deleteChordRule(id: selectedChordRuleID)
        self.selectedChordRuleID = nil
        chordSelectedNotes.removeAll()
        chordOutputCaptureArmed = false
        bindingMessage = "Chord 规则已删除。"
    }

    private func resetEditorState() {
        bindingTargetNote = nil
        selectedSingleNote = nil
        selectedChordRuleID = nil
        chordSelectedNotes.removeAll()
        chordDraftOutput = KeyStroke(keyCode: 8, modifiers: [.command])
        chordOutputCaptureArmed = false
        chordMultiSelectEnabled = false
        bindingMessage = "点击琴键进入绑定态；按 Esc 可取消。"
    }

    private func startChordOutputCapture() {
        bindingTargetNote = nil
        chordOutputCaptureArmed = true
        bindingMessage = "Chord 输出绑定中：请按下一个键位（支持修饰键）。"
    }

    private func handleChordOutputCapture(_ event: NSEvent) {
        if isEscapeEvent(event) {
            chordOutputCaptureArmed = false
            bindingMessage = "已取消 Chord 输出绑定。"
            return
        }

        if Self.modifierOnlyKeyCodes.contains(event.keyCode) {
            bindingMessage = "已忽略纯修饰键，请输入普通按键。"
            return
        }

        chordDraftOutput = KeyStroke(event: event).normalized()
        chordOutputCaptureArmed = false
        bindingMessage = "Chord 输出已绑定：\(chordDraftOutput.displayLabel)"
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [
        54, 55, // command
        56, 60, // shift
        57, // caps lock
        58, 61, // option
        59, 62, // control
        63 // function
    ]
}

private struct OneShotKeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        view.promoteToFirstResponder()
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.promoteToFirstResponder()
    }

    final class KeyCaptureNSView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            promoteToFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }

        fileprivate func promoteToFirstResponder() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window else { return }
                guard window.isKeyWindow else { return }
                if window.firstResponder !== self {
                    window.makeFirstResponder(self)
                }
            }
        }
    }
}
