import AppKit
import Observation
import SwiftUI

struct PianoMappingsEditorView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @State private var bindingTargetNote: Int?
    @State private var bindingMessage = "点击琴键进入绑定态；按 Esc 可取消。"

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            pianoArea
                .frame(maxWidth: .infinity, minHeight: 320, alignment: .top)

            sidebar
                .frame(width: 320)
        }
        .padding(16)
    }

    private var pianoArea: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                PianoKeyboardView(
                    noteRange: 48...83,
                    highlightedNotes: Set(viewModel.pressedNotes),
                    labelsForNote: labelsForNote,
                    onTapNote: beginBinding
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

                Text("选中规则属性面板将在 P2 完整接入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Rule Inspector")
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
        if event.keyCode == 53 {
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
                if window.firstResponder !== self {
                    window.makeFirstResponder(self)
                }
            }
        }
    }
}
