import AppKit
import Observation
import SwiftUI

struct PianoMappingsEditorView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @State private var bindingTargetNote: Int?
    @State private var bindingMessage = "点击琴键进入绑定态；按 Esc 可取消。"
    @State private var selectedChordRuleID: UUID?
    @State private var chordSelectedNotes: Set<Int> = []
    @State private var chordDraftAction: MappingAction = .keyCombo("cmd+c")
    @State private var selectedMelodyRuleID: UUID?
    @State private var melodyDraftNotes: [Int] = []
    @State private var melodyDraftAction: MappingAction = .text("hello ")
    @State private var melodyMaxIntervalMilliseconds: Int = 500
    @State private var isMelodyRecording = false

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
        .onChange(of: viewModel.activeProfileID) { _, _ in
            resetChordEditor()
            resetMelodyEditor()
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            if viewModel.selectedTab != .singleKey {
                bindingTargetNote = nil
            }
            if viewModel.selectedTab != .melody {
                isMelodyRecording = false
            }
        }
        .onChange(of: viewModel.latestNoteOnSequence) { _, _ in
            guard viewModel.selectedTab == .melody,
                  isMelodyRecording,
                  let note = viewModel.latestNoteOn else {
                return
            }

            appendMelodyNote(note: note, source: "MIDI")
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
            ProfileSectionView(viewModel: viewModel)
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
                    Text("Single Key：点击琴键后输入单字符即可绑定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .chord:
                    chordInspector
                case .melody:
                    melodyInspector
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
                                        Text("\(rule.action.type.rawValue): \(rule.action.value)")
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

            MappingActionEditorView(action: $chordDraftAction)

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

    private var melodyInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Melody Rules")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("New") {
                    startNewMelodyRule()
                }
                .buttonStyle(.bordered)
            }

            if melodyRules.isEmpty {
                Text("暂无 Melody 规则")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(melodyRules) { rule in
                            Button {
                                selectMelodyRule(rule)
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(MIDINoteParser.stringify(notes: rule.notes, separator: " "))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text("\(rule.maxIntervalMilliseconds)ms · \(rule.action.type.rawValue): \(rule.action.value)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(rule.id == selectedMelodyRuleID ? Color.accentColor.opacity(0.18) : Color(nsColor: .textBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 130)
            }

            HStack(spacing: 8) {
                if isMelodyRecording {
                    Button("Stop Recording") {
                        toggleMelodyRecording()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Recording") {
                        toggleMelodyRecording()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Clear") {
                    clearMelodyDraftNotes()
                }
                .buttonStyle(.bordered)
            }

            Text("Sequence: \(MIDINoteParser.stringify(notes: melodyDraftNotes, separator: " "))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(value: $melodyMaxIntervalMilliseconds, in: 100...4000, step: 50) {
                Text("Max Interval: \(melodyMaxIntervalMilliseconds)ms")
                    .font(.caption)
            }

            MappingActionEditorView(action: $melodyDraftAction)

            HStack(spacing: 8) {
                Button("Save") {
                    saveMelodyRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(melodyDraftNotes.isEmpty)

                Button("Delete", role: .destructive) {
                    deleteSelectedMelodyRule()
                }
                .buttonStyle(.bordered)
                .disabled(selectedMelodyRuleID == nil)
            }

            Text("录制模式仅采集 MIDI noteOn；也可直接点击键盘点选序列。")
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
                        get: { viewModel.activeProfile?.payload.velocityEnabled ?? false },
                        set: { viewModel.setVelocityEnabled($0) }
                    )
                )

                HStack {
                    Text("Default Threshold")

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.activeProfile?.payload.defaultVelocityThreshold ?? 100) },
                            set: { viewModel.setVelocityThreshold(Int($0.rounded())) }
                        ),
                        in: 1...127,
                        step: 1
                    )

                    Text("\(viewModel.activeProfile?.payload.defaultVelocityThreshold ?? 100)")
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
        guard let profile = viewModel.activeProfile else { return [:] }
        return profile.payload.singleKeyRules.reduce(into: [:]) { partialResult, rule in
            partialResult[rule.note] = rule.normalOutput
        }
    }

    private var chordRules: [ChordMappingRule] {
        guard let rules = viewModel.activeProfile?.payload.chordRules else { return [] }
        return rules.sorted { lhs, rhs in
            let lhsKey = MIDINoteParser.stringify(notes: lhs.notes, separator: " ")
            let rhsKey = MIDINoteParser.stringify(notes: rhs.notes, separator: " ")
            return lhsKey < rhsKey
        }
    }

    private var melodyRules: [MelodyMappingRule] {
        guard let rules = viewModel.activeProfile?.payload.melodyRules else { return [] }
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
        case .melody:
            return Set(melodyDraftNotes)
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
        bindingMessage = "正在绑定 \(MIDINote(note).name)：请输入 1 个可显示字符（Esc 取消）。"
    }

    private func handlePianoTap(note: Int) {
        switch viewModel.selectedTab {
        case .singleKey:
            beginBinding(note: note)
        case .chord:
            toggleChordNoteSelection(note: note)
        case .melody:
            appendMelodyNote(note: note, source: "点选")
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
            bindingMessage = "已忽略纯修饰键，请输入可显示单字符。"
            return
        }

        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        if !event.modifierFlags.intersection(blockedModifiers).isEmpty {
            bindingMessage = "请勿使用 Command/Control/Option 组合键。"
            return
        }

        guard let output = normalizedOutputCharacter(from: event) else {
            bindingMessage = "仅支持可显示的单字符（不支持回车/制表等）。"
            return
        }

        viewModel.setSingleKeyMapping(note: note, output: output)
        bindingTargetNote = nil
        bindingMessage = "已绑定 \(MIDINote(note).name)：Out=\(output) / High=\(output.uppercased())"
    }

    private func normalizedOutputCharacter(from event: NSEvent) -> String? {
        guard let characters = event.characters, characters.count == 1,
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
            return nil
        }

        return String(characters)
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
        chordDraftAction = rule.action
        bindingMessage = "已选中 Chord 规则：\(MIDINoteParser.stringify(notes: rule.notes, separator: " "))"
    }

    private func startNewChordRule() {
        selectedChordRuleID = nil
        chordSelectedNotes.removeAll()
        chordDraftAction = .keyCombo("cmd+c")
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
                ChordMappingRule(id: selectedChordRuleID, notes: notes, action: chordDraftAction)
            )
            bindingMessage = "Chord 规则已更新。"
        } else {
            viewModel.createChordRule(notes: notes, action: chordDraftAction)
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
        chordDraftAction = .keyCombo("cmd+c")
    }

    private func toggleMelodyRecording() {
        isMelodyRecording.toggle()
        if isMelodyRecording {
            bindingMessage = "Melody 录制已开始：请按 MIDI 键。"
        } else {
            bindingMessage = "Melody 录制已停止。"
        }
    }

    private func appendMelodyNote(note: Int, source: String) {
        let clamped = max(0, min(127, note))
        melodyDraftNotes.append(clamped)
        bindingMessage = "\(source) 追加 \(MIDINote(clamped).name)。"
    }

    private func clearMelodyDraftNotes() {
        melodyDraftNotes.removeAll()
        bindingMessage = "Melody 序列已清空。"
    }

    private func selectMelodyRule(_ rule: MelodyMappingRule) {
        selectedMelodyRuleID = rule.id
        melodyDraftNotes = rule.notes
        melodyMaxIntervalMilliseconds = rule.maxIntervalMilliseconds
        melodyDraftAction = rule.action
        isMelodyRecording = false
        bindingMessage = "已选中 Melody 规则。"
    }

    private func startNewMelodyRule() {
        selectedMelodyRuleID = nil
        melodyDraftNotes.removeAll()
        melodyMaxIntervalMilliseconds = 500
        melodyDraftAction = .text("hello ")
        isMelodyRecording = false
        bindingMessage = "已进入新建 Melody 规则模式。"
    }

    private func saveMelodyRule() {
        let notes = melodyDraftNotes.map { max(0, min(127, $0)) }
        guard !notes.isEmpty else {
            bindingMessage = "请先录制或点选 Melody 序列。"
            return
        }

        if let selectedMelodyRuleID {
            viewModel.updateMelodyRule(
                MelodyMappingRule(
                    id: selectedMelodyRuleID,
                    notes: notes,
                    maxIntervalMilliseconds: melodyMaxIntervalMilliseconds,
                    action: melodyDraftAction
                )
            )
            bindingMessage = "Melody 规则已更新。"
        } else {
            viewModel.createMelodyRule(
                notes: notes,
                maxIntervalMilliseconds: melodyMaxIntervalMilliseconds,
                action: melodyDraftAction
            )
            startNewMelodyRule()
            bindingMessage = "Melody 规则已创建，并已清空编辑态。"
        }
    }

    private func deleteSelectedMelodyRule() {
        guard let selectedMelodyRuleID else { return }
        viewModel.deleteMelodyRule(id: selectedMelodyRuleID)
        startNewMelodyRule()
        bindingMessage = "Melody 规则已删除。"
    }

    private func resetMelodyEditor() {
        selectedMelodyRuleID = nil
        melodyDraftNotes.removeAll()
        melodyDraftAction = .text("hello ")
        melodyMaxIntervalMilliseconds = 500
        isMelodyRecording = false
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
