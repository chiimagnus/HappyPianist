import AppKit
import Observation
import SwiftUI

struct PianoMappingsEditorView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @State private var bindingTargetNote: Int?
    @State private var bindingMessage = "点击琴键进入绑定态；按 Esc 可取消。"
    @State private var selectedChordRuleID: UUID?
    @State private var chordSelectedNotes: Set<Int> = []
    @State private var chordDraftOutput: KeyStroke = KeyStroke(keyCode: 8, modifiers: [.command])

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            pianoArea
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .top)

            sidebar
                .frame(width: 320)
        }
        .padding(16)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            cancelBindingOnFocusLoss()
        }
        .onChange(of: viewModel.activeConfig?.id) { _, _ in
            resetChordEditor()
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            if viewModel.selectedTab != .singleKey {
                bindingTargetNote = nil
            }
        }
    }

    private var pianoArea: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                PianoKeyboardView(
                    noteRange: 48...83,
                    highlightedNotes: Set(viewModel.pressedNotes),
                    selectedNotes: selectedNotesForCurrentMode,
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeAndInspectorPanel
            velocityPanel
        }
    }

    private var modeAndInspectorPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(LonelyPianistViewModel.EditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.selectedTab {
                case .singleKey:
                    Text("Single Key：点击琴键后输入一个按键即可绑定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .chord:
                    chordInspector
                }
            }
        } label: {
            Text("Rule Inspector")
        }
    }

    private var chordInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chord Rules")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("New") {
                    startNewChordRule()
                }
                .buttonStyle(.bordered)
            }

            if chordRules.isEmpty {
                Text("暂无 Chord 规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(chordRules) { rule in
                            Button {
                                selectChordRule(rule)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(MIDINoteParser.stringify(notes: rule.notes, separator: " "))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("Out: \(rule.output.displayLabel)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(rule.id == selectedChordRuleID ? Color.accentColor.opacity(0.18) : Color(nsColor: .textBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 140)
            }

            Text("Selected: \(MIDINoteParser.stringify(notes: chordSelectedNotes.sorted(), separator: " "))")
                .font(.caption)
                .foregroundStyle(.secondary)

            keyStrokeEditor(title: "Output", keyStroke: $chordDraftOutput)

            HStack(spacing: 8) {
                Button("Save") {
                    saveChordRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(chordSelectedNotes.isEmpty)

                Button("Delete", role: .destructive) {
                    deleteSelectedChordRule()
                }
                .buttonStyle(.bordered)
                .disabled(selectedChordRuleID == nil)
            }

            Text("Chord 触发采用严格相等：当前按下 notes 必须与规则 notes 完全一致。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var velocityPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Enable Velocity",
                    isOn: Binding(
                        get: { viewModel.activeConfig?.payload.velocityEnabled ?? false },
                        set: { viewModel.setVelocityEnabled($0) }
                    )
                )

                HStack {
                    Text("Default Threshold")

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.activeConfig?.payload.defaultVelocityThreshold ?? 100) },
                            set: { viewModel.setVelocityThreshold(Int($0.rounded())) }
                        ),
                        in: 1...127,
                        step: 1
                    )

                    Text("\(viewModel.activeConfig?.payload.defaultVelocityThreshold ?? 100)")
                        .frame(width: 30)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text("Velocity")
        }
    }

    private var singleRuleOutputByNote: [Int: String] {
        guard let config = viewModel.activeConfig else { return [:] }
        return config.payload.singleKeyRules.reduce(into: [:]) { partialResult, rule in
            partialResult[rule.note] = rule.output.displayLabel
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

    private var selectedNotesForCurrentMode: Set<Int> {
        switch viewModel.selectedTab {
        case .singleKey:
            return []
        case .chord:
            return chordSelectedNotes
        }
    }

    private func labelsForNote(_ note: Int) -> PianoKeyLabels {
        PianoKeyLabels(
            noteName: MIDINote(note).name,
            mappingLabel: singleRuleOutputByNote[note]
        )
    }

    private func beginBinding(note: Int) {
        guard viewModel.selectedTab == .singleKey else {
            bindingMessage = "请先切换到 Single Key 模式再绑定。"
            return
        }

        bindingTargetNote = note
        bindingMessage = "正在绑定 \(MIDINote(note).name)：请输入 1 个按键（Esc 取消）。"
    }

    private func handlePianoTap(note: Int) {
        switch viewModel.selectedTab {
        case .singleKey:
            beginBinding(note: note)
        case .chord:
            toggleChordNoteSelection(note: note)
        }
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

        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(blockedModifiers).isEmpty {
            bindingMessage = "请勿使用 Command/Control/Option 组合键。"
            return
        }

        viewModel.setSingleKeyMapping(note: note, keyCode: event.keyCode)
        bindingTargetNote = nil
        let normal = KeyStroke(keyCode: event.keyCode)
        let high = normal.adding(.shift)
        bindingMessage = "已绑定 \(MIDINote(note).name)：Out=\(normal.displayLabel) / High=\(high.displayLabel)"
    }

    private func isEscapeEvent(_ event: NSEvent) -> Bool {
        event.keyCode == 53 || event.characters == "\u{1B}"
    }

    private func cancelBindingOnFocusLoss() {
        guard let note = bindingTargetNote else { return }
        bindingTargetNote = nil
        bindingMessage = "窗口失焦，已取消绑定 \(MIDINote(note).name)。"
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
        bindingMessage = "已选中 Chord 规则：\(MIDINoteParser.stringify(notes: rule.notes, separator: " "))"
    }

    private func startNewChordRule() {
        selectedChordRuleID = nil
        chordSelectedNotes.removeAll()
        chordDraftOutput = KeyStroke(keyCode: 8, modifiers: [.command])
        bindingMessage = "已进入新建 Chord 规则模式。"
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
            startNewChordRule()
            bindingMessage = "Chord 规则已创建，并已清空编辑态。"
        }
    }

    private func deleteSelectedChordRule() {
        guard let selectedChordRuleID else { return }
        viewModel.deleteChordRule(id: selectedChordRuleID)
        startNewChordRule()
        bindingMessage = "Chord 规则已删除。"
    }

    private func resetChordEditor() {
        selectedChordRuleID = nil
        chordSelectedNotes.removeAll()
        chordDraftOutput = KeyStroke(keyCode: 8, modifiers: [.command])
    }

    @ViewBuilder
    private func keyStrokeEditor(title: String, keyStroke: Binding<KeyStroke>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title): \(keyStroke.wrappedValue.displayLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("KeyCode")
                    .font(.caption)
                TextField(
                    "0",
                    value: keyCodeBinding(for: keyStroke),
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            }

            HStack(spacing: 10) {
                Toggle("\u{2318}", isOn: modifierBinding(for: keyStroke, modifier: .command))
                Toggle("\u{2325}", isOn: modifierBinding(for: keyStroke, modifier: .option))
                Toggle("\u{2303}", isOn: modifierBinding(for: keyStroke, modifier: .control))
                Toggle("\u{21E7}", isOn: modifierBinding(for: keyStroke, modifier: .shift))
            }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
    }

    private func keyCodeBinding(for keyStroke: Binding<KeyStroke>) -> Binding<Int> {
        Binding(
            get: { Int(keyStroke.wrappedValue.keyCode) },
            set: { rawValue in
                let clamped = max(0, min(rawValue, Int(UInt16.max)))
                keyStroke.wrappedValue.keyCode = UInt16(clamped)
            }
        )
    }

    private func modifierBinding(for keyStroke: Binding<KeyStroke>, modifier: KeyStrokeModifiers) -> Binding<Bool> {
        Binding(
            get: { keyStroke.wrappedValue.modifiers.contains(modifier) },
            set: { isEnabled in
                if isEnabled {
                    keyStroke.wrappedValue.modifiers.insert(modifier)
                } else {
                    keyStroke.wrappedValue.modifiers.remove(modifier)
                }
            }
        )
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
