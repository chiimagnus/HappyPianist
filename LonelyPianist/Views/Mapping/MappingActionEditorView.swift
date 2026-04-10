import SwiftUI

struct MappingActionEditorView: View {
    @Binding var action: MappingAction

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action Type", selection: $action.type) {
                ForEach(MappingActionType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)

            TextField(valuePlaceholder, text: $action.value)
                .textFieldStyle(.roundedBorder)

            if action.type == .keyCombo {
                if let keyComboErrorMessage {
                    Label(keyComboErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !action.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Key combo 格式有效", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var valuePlaceholder: String {
        switch action.type {
        case .text:
            return "Text output"
        case .keyCombo:
            return "例如 cmd+k"
        case .shortcut:
            return "Shortcut 名称"
        }
    }

    private var keyComboErrorMessage: String? {
        let trimmed = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "请输入组合键，例如 cmd+k" }

        do {
            _ = try KeyComboParser.parse(trimmed)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

#Preview {
    StatefulPreviewWrapper(MappingAction(type: .keyCombo, value: "cmd+k")) { action in
        MappingActionEditorView(action: action)
            .padding()
            .frame(width: 360)
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ value: Value, content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: value)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}
