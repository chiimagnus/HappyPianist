import Observation
import SwiftUI

struct RecorderLibraryView: View {
    @Bindable var viewModel: PianoKeyViewModel

    @State private var renamingTakeID: UUID?
    @State private var renameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Library")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            List(selection: selectionBinding) {
                ForEach(viewModel.takes) { take in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(take.name)
                            .font(.body.weight(.medium))
                        Text("\(take.notes.count) notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(take.id)
                    .contextMenu {
                        Button("Rename") {
                            renamingTakeID = take.id
                            renameDraft = take.name
                        }
                        Button("Delete", role: .destructive) {
                            viewModel.deleteTake(take.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Instrument")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Grand Piano", systemImage: "pianokeys")
                    .font(.subheadline.weight(.medium))
            }
            .padding(12)
        }
        .alert("Rename Take", isPresented: renameAlertBinding) {
            TextField("Take name", text: $renameDraft)
            Button("Save") {
                guard let renamingTakeID else { return }
                viewModel.renameTake(renamingTakeID, to: renameDraft)
                self.renamingTakeID = nil
            }
            Button("Cancel", role: .cancel) {
                renamingTakeID = nil
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingTakeID != nil },
            set: { isPresented in
                if !isPresented {
                    renamingTakeID = nil
                }
            }
        )
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedTakeID },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectTake(newValue)
            }
        )
    }
}

