import MIDI
import Observation
import SwiftUI

struct MIDISettingsView: View {
    @Bindable var viewModel: MIDISettingsViewModel

    var body: some View {
        List {
            Section("MIDI 输入") {
                Button {
                    viewModel.selectInput(endpointUniqueID: nil)
                } label: {
                    MIDIEndpointRow(
                        title: "暂不选择输入",
                        isSelected: viewModel.selectedInputEndpointID == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(viewModel.inputEndpoints) { endpoint in
                    Button {
                        viewModel.selectInput(endpointUniqueID: endpoint.id)
                    } label: {
                        MIDIEndpointRow(
                            title: endpoint.name,
                            isSelected: viewModel.selectedInputEndpointID == endpoint.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        viewModel.selectedInputEndpointID == endpoint.id ? "已选择" : "未选择"
                    )
                }

                switch viewModel.inputSelectionState {
                case .notSelected, .connected:
                    EmptyView()
                case .unavailable:
                    Text("所选输入不可用。重新连接后请手动重新选择；不会自动切换到其他设备。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("MIDI 输出（可选）") {
                Button {
                    viewModel.selectOutput(endpointUniqueID: nil)
                } label: {
                    MIDIEndpointRow(
                        title: "不使用输出",
                        isSelected: viewModel.selectedOutputEndpointID == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(viewModel.outputEndpoints) { endpoint in
                    Button {
                        viewModel.selectOutput(endpointUniqueID: endpoint.id)
                    } label: {
                        MIDIEndpointRow(
                            title: endpoint.name,
                            isSelected: viewModel.selectedOutputEndpointID == endpoint.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        viewModel.selectedOutputEndpointID == endpoint.id ? "已选择" : "未选择"
                    )
                }

                switch viewModel.outputSelectionState {
                case .notSelected, .available:
                    EmptyView()
                case .unavailable:
                    Text("所选输出不可用。练习判定仍可使用输入；播放功能会保持不可用。")
                        .foregroundStyle(.secondary)
                }
            }

            Section("连接安全") {
                Text("不要把所选 MIDI 输出回接到所选输入。若设备具备 MIDI‑Thru 或软件回环，请先断开或手动验证后再开始练习。")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    HStack {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("关闭", action: viewModel.dismissError)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("MIDI 设备")
        .toolbar {
            Button("刷新设备", systemImage: "arrow.clockwise") {
                viewModel.refreshEndpoints()
            }
        }
        .task {
            viewModel.load()
        }
    }
}

private struct MIDIEndpointRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
    }
}
