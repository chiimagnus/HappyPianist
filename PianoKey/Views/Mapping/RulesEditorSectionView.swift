import Observation
import SwiftUI

struct RulesEditorSectionView: View {
    @Bindable var viewModel: PianoKeyViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Mode", selection: $viewModel.selectedTab) {
                    ForEach(PianoKeyViewModel.EditorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.selectedTab {
                case .singleKey:
                    singleRuleEditor
                case .chord:
                    chordRuleEditor
                case .melody:
                    melodyRuleEditor
                }

                velocityEditor
            }
        } label: {
            Text("Rules")
        }
    }

    private var singleRuleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Single Key Rules")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Add") { viewModel.addSingleRule() }
                    .buttonStyle(.bordered)
            }

            ForEach(viewModel.activeProfile?.payload.singleKeyRules ?? []) { rule in
                HStack(spacing: 8) {
                    Stepper(
                        value: Binding(
                            get: { rule.note },
                            set: { newNote in
                                var updated = rule
                                updated.note = newNote
                                viewModel.updateSingleRule(updated)
                            }
                        ),
                        in: 0...127
                    ) {
                        Text(MIDINote(rule.note).name)
                            .frame(width: 58, alignment: .leading)
                    }

                    TextField(
                        "Out",
                        text: Binding(
                            get: { rule.normalOutput },
                            set: { newOutput in
                                var updated = rule
                                updated.normalOutput = newOutput
                                viewModel.updateSingleRule(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                    TextField(
                        "High",
                        text: Binding(
                            get: { rule.highVelocityOutput ?? "" },
                            set: { newOutput in
                                var updated = rule
                                updated.highVelocityOutput = newOutput.isEmpty ? nil : newOutput
                                viewModel.updateSingleRule(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                    Stepper(
                        value: Binding(
                            get: { rule.velocityThreshold ?? viewModel.activeProfile?.payload.defaultVelocityThreshold ?? 100 },
                            set: { newThreshold in
                                var updated = rule
                                updated.velocityThreshold = newThreshold
                                viewModel.updateSingleRule(updated)
                            }
                        ),
                        in: 1...127
                    ) {
                        Text("T:\(rule.velocityThreshold ?? 0)")
                            .font(.caption)
                            .frame(width: 46, alignment: .leading)
                    }

                    Button(role: .destructive) {
                        viewModel.removeSingleRule(rule.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chordRuleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chord Rules")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Add") { viewModel.addChordRule() }
                    .buttonStyle(.bordered)
            }

            ForEach(viewModel.activeProfile?.payload.chordRules ?? []) { rule in
                HStack(spacing: 8) {
                    TextField(
                        "Notes",
                        text: Binding(
                            get: { MIDINoteParser.stringify(notes: rule.notes, separator: " ") },
                            set: { newValue in
                                let parsed = MIDINoteParser.parseNotes(newValue)
                                guard !parsed.isEmpty else { return }
                                var updated = rule
                                updated.notes = parsed
                                viewModel.updateChordRule(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                    Picker(
                        "Type",
                        selection: Binding(
                            get: { rule.action.type },
                            set: { newType in
                                var updated = rule
                                updated.action.type = newType
                                viewModel.updateChordRule(updated)
                            }
                        )
                    ) {
                        ForEach(MappingActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 88)

                    TextField(
                        "Action",
                        text: Binding(
                            get: { rule.action.value },
                            set: { newValue in
                                var updated = rule
                                updated.action.value = newValue
                                viewModel.updateChordRule(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        viewModel.removeChordRule(rule.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var melodyRuleEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Melody Rules")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Add") { viewModel.addMelodyRule() }
                    .buttonStyle(.bordered)
            }

            ForEach(viewModel.activeProfile?.payload.melodyRules ?? []) { rule in
                HStack(spacing: 8) {
                    TextField(
                        "Notes",
                        text: Binding(
                            get: { MIDINoteParser.stringify(notes: rule.notes, separator: " ") },
                            set: { newValue in
                                let parsed = MIDINoteParser.parseNotes(newValue)
                                guard !parsed.isEmpty else { return }
                                var updated = rule
                                updated.notes = parsed
                                viewModel.updateMelodyRule(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                    Stepper(
                        value: Binding(
                            get: { rule.maxIntervalMilliseconds },
                            set: { newInterval in
                                var updated = rule
                                updated.maxIntervalMilliseconds = newInterval
                                viewModel.updateMelodyRule(updated)
                            }
                        ),
                        in: 100...2000,
                        step: 50
                    ) {
                        Text("\(rule.maxIntervalMilliseconds)ms")
                            .font(.caption)
                            .frame(width: 82, alignment: .leading)
                    }

                    Picker(
                        "Type",
                        selection: Binding(
                            get: { rule.action.type },
                            set: { newType in
                                var updated = rule
                                updated.action.type = newType
                                viewModel.updateMelodyRule(updated)
                            }
                        )
                    ) {
                        ForEach(MappingActionType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 88)

                    TextField(
                        "Action",
                        text: Binding(
                            get: { rule.action.value },
                            set: { newValue in
                                var updated = rule
                                updated.action.value = newValue
                                viewModel.updateMelodyRule(updated)
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        viewModel.removeMelodyRule(rule.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var velocityEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

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
                    .frame(width: 28)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

