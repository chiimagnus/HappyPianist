import Observation
import SwiftUI

struct ProfileSectionView: View {
    @Bindable var viewModel: LonelyPianistViewModel
    @State private var newProfileName = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Active Profile", selection: activeProfileBinding) {
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)

                if let activeProfile = viewModel.activeProfile {
                    TextField(
                        "Profile Name",
                        text: Binding(
                            get: { activeProfile.name },
                            set: { viewModel.updateProfileName($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    TextField("New profile", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        viewModel.createProfile(named: newProfileName)
                        newProfileName = ""
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 8) {
                    Button("Duplicate") {
                        viewModel.duplicateActiveProfile()
                    }
                    .buttonStyle(.bordered)

                    Button("Delete") {
                        if let activeID = viewModel.activeProfileID {
                            viewModel.deleteProfile(activeID)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.profiles.count <= 1)
                }
            }
        } label: {
            Text("Profiles")
        }
    }

    private var activeProfileBinding: Binding<UUID> {
        Binding(
            get: {
                viewModel.activeProfileID ?? viewModel.profiles.first?.id ?? UUID()
            },
            set: { newID in
                viewModel.setActiveProfile(newID)
            }
        )
    }
}

