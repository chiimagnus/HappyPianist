import Observation
import SwiftUI

struct KeyboardMapSectionView: View {
    @Bindable var viewModel: LonelyPianistViewModel

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 6)

    var body: some View {
        GroupBox {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleRules) { rule in
                    VStack(spacing: 4) {
                        Text(MIDINote(rule.note).name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(rule.normalOutput)
                            .font(.body.monospaced())
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                }
            }
        } label: {
            Text("Single Key Map")
        }
    }

    private var visibleRules: [SingleKeyMappingRule] {
        guard let profile = viewModel.activeProfile else { return [] }
        return Array(profile.payload.singleKeyRules.sorted(by: { $0.note < $1.note }).prefix(24))
    }
}

