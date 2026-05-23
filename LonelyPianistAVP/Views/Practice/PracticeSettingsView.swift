import SwiftUI

struct PracticeSettingsView: View {
    @Binding var virtualPerformerEnabled: Bool
    let backendStatusText: String?
    let lastImprovStatusText: String?
    let recordingSourceText: String?
    let isAIPerformanceActive: Bool
    let isVirtualPianoMode: Bool
    let isBluetoothMIDIMode: Bool
    let gazePlaneDiskStatusText: String?
    let onOpenTakeLibrary: () -> Void
    let onRetryVirtualPianoPlacement: () -> Void
    let onRequestSessionRebuild: () -> Void

    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage(AudioOutputVolumeSettings.userDefaultsKey)
    private var audioOutputVolume = Double(AudioOutputVolumeSettings.defaultValue)
    @AppStorage(PracticeSessionSettingsKeys.manualAdvanceMode) private var manualAdvanceModeRawValue = ManualAdvanceMode.step.rawValue
    @AppStorage(PracticeSessionSettingsKeys.handMode) private var practiceHandModeRawValue = PracticeHandMode.both.rawValue
    @AppStorage(PracticeSessionSettingsKeys.improvBackendKind)
    private var improvBackendKindRawValue = ImprovBackendKind.networkBonjourHTTP.rawValue
    @AppStorage(PracticeSessionSettingsKeys.soundOutputRoute)
    private var soundOutputRouteRawValue = PracticeSoundOutputRoute.localSampler.rawValue
    @AppStorage(PracticeSessionSettingsKeys.midiDestinationUniqueID)
    private var midiDestinationUniqueID = 0
    @AppStorage(PracticeSessionSettingsKeys.sendLocalControlOff)
    private var sendLocalControlOff = false

    @State private var destinationConnectionViewModel = MIDIDestinationConnectionViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("输出音量（AVP）")
                HStack {
                    Slider(value: $audioOutputVolume, in: 0 ... 1)
                    Text(audioOutputVolume, format: .percent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
                Text("调到 0 可避免与真实钢琴叠音。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if isBluetoothMIDIMode {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("发声路由", selection: $soundOutputRouteRawValue) {
                        ForEach(PracticeSoundOutputRoute.allCases) { route in
                            Text(route.title).tag(route.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        Picker("MIDI 输出目的地", selection: $midiDestinationUniqueID) {
                            Text("未选择").tag(0)
                            ForEach(destinationConnectionViewModel.destinations) { destination in
                                Text(destination.name).tag(Int(destination.id))
                            }
                        }
                        .pickerStyle(.menu)

                        Button("刷新输出", systemImage: "arrow.clockwise") {
                            destinationConnectionViewModel.refreshDestinations()
                        }
                        .buttonStyle(.bordered)
                    }

                    Toggle("Local Control Off（可选）", isOn: $sendLocalControlOff)

                    Text("变更路由/目的地会重启当前练习会话（进度可能重置）。输出音量不会受影响。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("应用路由变更并重启会话", systemImage: "arrow.clockwise") {
                        onRequestSessionRebuild()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()

                    if let message = destinationConnectionViewModel.lastErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    destinationConnectionViewModel.start()
                }
                .onDisappear {
                    destinationConnectionViewModel.stop()
                }
                .onChange(of: sendLocalControlOff) {
                    applyLocalControlOffIfNeeded()
                }
                .onChange(of: midiDestinationUniqueID) {
                    applyLocalControlOffIfNeeded()
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle("AI 即兴演奏（虚拟演奏家）", isOn: $virtualPerformerEnabled)
                if virtualPerformerEnabled {
                    Picker("即兴后端", selection: $improvBackendKindRawValue) {
                        ForEach(ImprovBackendKind.allCases) { kind in
                            Text(backendTitle(kind)).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.menu)

                    if let effectiveBackendStatusText {
                        Text(effectiveBackendStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let lastImprovStatusText {
                        Text(lastImprovStatusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                if let recordingSourceText {
                    Text(recordingSourceText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("打开录制库", systemImage: "list.bullet") {
                    onOpenTakeLibrary()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()

                Divider()

                Toggle("调试：显示键盘坐标轴（X/Y/Z）", isOn: $debugKeyboardAxesOverlayEnabled)

                Divider()

                Picker("练习手", selection: $practiceHandModeRawValue) {
                    ForEach(PracticeHandMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("手动前进方式", selection: $manualAdvanceModeRawValue) {
                    ForEach(ManualAdvanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if isVirtualPianoMode {
                    Divider()

                    if let gazePlaneDiskStatusText {
                        Text(gazePlaneDiskStatusText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Button("重试放置", systemImage: "arrow.clockwise") {
                        onRetryVirtualPianoPlacement()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()
                }
            }
            .disabled(isAIPerformanceActive)
        }
        .padding(16)
        .frame(minWidth: 320)
    }

    private func applyLocalControlOffIfNeeded() {
        guard midiDestinationUniqueID != 0 else { return }
        guard let destinationUniqueID = Int32(exactly: midiDestinationUniqueID) else { return }
        destinationConnectionViewModel.sendLocalControlOff(sendLocalControlOff, destinationUniqueID: destinationUniqueID)
    }

    private var effectiveBackendStatusText: String? {
        guard let selectedKind = ImprovBackendKind(rawValue: improvBackendKindRawValue) else {
            return "Backend: invalid kind"
        }

        switch selectedKind {
        case .networkBonjourHTTP:
            return backendStatusText ?? "Backend: network"
        case .localDeterministic:
            return "Backend: local deterministic"
        case .localRule:
            return "Backend: local rule"
        case .tickRangeReplay:
            return "Backend: tick-range replay"
        }
    }

    private func backendTitle(_ kind: ImprovBackendKind) -> String {
        switch kind {
        case .networkBonjourHTTP:
            "网络本地连接（电脑端 Python）"
        case .localDeterministic:
            "本地 deterministic（AVP）"
        case .localRule:
            "本地 rule（AVP）"
        case .tickRangeReplay:
            "按谱片段回放（tick-range replay）"
        }
    }
}

#Preview("练习设置") {
    PracticeSettingsView(
        virtualPerformerEnabled: .constant(false),
        backendStatusText: nil,
        lastImprovStatusText: nil,
        recordingSourceText: "录制来源：Bluetooth MIDI（弹奏琴键即可录制）",
        isAIPerformanceActive: false,
        isVirtualPianoMode: true,
        isBluetoothMIDIMode: true,
        gazePlaneDiskStatusText: "GazePlaneDisk: OK",
        onOpenTakeLibrary: {},
        onRetryVirtualPianoPlacement: {},
        onRequestSessionRebuild: {}
    )
}
