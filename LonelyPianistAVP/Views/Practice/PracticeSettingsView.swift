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
    let isRecording: Bool
    let recordingElapsedText: String
    let canStartRecording: Bool
    let onBackToLibrary: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onOpenTakeLibrary: () -> Void
    let onRetryVirtualPianoPlacement: () -> Void
    let onRequestSessionRebuild: () -> Void
    let onDebugInjectAIImprovPhrase: () -> Void

    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage(AudioOutputVolumeSettings.userDefaultsKey)
    private var audioOutputVolume = Double(AudioOutputVolumeSettings.defaultValue)
    @AppStorage(PracticeSessionSettingsKeys.manualAdvanceMode) private var manualAdvanceModeRawValue = ManualAdvanceMode.step.rawValue
    @AppStorage(PracticeSessionSettingsKeys.handMode) private var practiceHandModeRawValue = PracticeHandMode.both.rawValue
    @AppStorage(PracticeSessionSettingsKeys.improvBackendKind)
    private var improvBackendKindRawValue = ImprovBackendSelection.defaultKind.rawValue
    @AppStorage(PracticeSessionSettingsKeys.soundOutputRoute)
    private var soundOutputRouteRawValue = PracticeSoundOutputRoute.localSampler.rawValue
    @AppStorage(PracticeSessionSettingsKeys.midiDestinationUniqueID)
    private var midiDestinationUniqueID = 0
    @AppStorage(PracticeSessionSettingsKeys.sendLocalControlOff)
    private var sendLocalControlOff = false

    @State private var destinationConnectionViewModel = MIDIDestinationConnectionViewModel()
    @State private var isAdvancedFeaturesExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("回到选曲库", systemImage: "chevron.backward") {
                    onBackToLibrary()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()

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
                            .buttonBorderShape(.roundedRectangle)
                            .hoverEffect()
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
                }

                VStack(alignment: .leading, spacing: 12) {
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
                }
                .disabled(isAIPerformanceActive)

                DisclosureGroup(isExpanded: $isAdvancedFeaturesExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("输出音量（AVP）")
                                .font(.callout)
                            Slider(value: $audioOutputVolume, in: 0 ... 1, step: 0.1)
                            Text("调到 0 可避免与真实钢琴叠音。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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

                                #if DEBUG
                                    Button("调试：注入测试短句（跨键盘）", systemImage: "hammer") {
                                        onDebugInjectAIImprovPhrase()
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.roundedRectangle)
                                    .hoverEffect()

                                    Text("用于 simulator：不依赖 Hand Tracking，直接触发 AI 生成/回放。")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                #endif
                            }
                        }
                        .disabled(isAIPerformanceActive)

                        VStack(alignment: .leading, spacing: 12) {
                            if isRecording {
                                Button("结束录制", systemImage: "stop.circle.fill") {
                                    onStopRecording()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .buttonBorderShape(.roundedRectangle)
                                .hoverEffect()

                                Text(recordingElapsedText)
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                            } else {
                                Button("开始录制", systemImage: "circle.fill") {
                                    onStartRecording()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .buttonBorderShape(.roundedRectangle)
                                .hoverEffect()
                                .disabled(canStartRecording == false)
                            }

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
                        }
                        .disabled(isAIPerformanceActive)

                        Toggle("显示键盘坐标轴（X/Y/Z）", isOn: $debugKeyboardAxesOverlayEnabled)
                        .disabled(isAIPerformanceActive)
                    }
                    .padding(.top, 12)
                } label: {
                    Label("高级功能", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                if isVirtualPianoMode {
                    VStack(alignment: .leading, spacing: 12) {
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
                    .disabled(isAIPerformanceActive)
                }

            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
        .onAppear {
            migrateLegacyBackendKindIfNeeded()
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func applyLocalControlOffIfNeeded() {
        guard midiDestinationUniqueID != 0 else { return }
        guard let destinationUniqueID = Int32(exactly: midiDestinationUniqueID) else { return }
        destinationConnectionViewModel.sendLocalControlOff(sendLocalControlOff, destinationUniqueID: destinationUniqueID)
    }

    private var effectiveBackendStatusText: String? {
        guard let selectedKind = ImprovBackendKind(rawValue: improvBackendKindRawValue) else {
            return backendStatusText ?? "即兴后端设置已变更，请重新选择。"
        }

        switch selectedKind {
        case .networkBonjourHTTPAriaV2:
            return backendStatusText ?? "后端：网络本地连接（Aria v2）"
        case .networkBonjourWebSocketAriaV2:
            return backendStatusText ?? "后端：网络本地连接（Aria v2 Streaming）"
        case .localCoreMLDuet:
            return backendStatusText ?? "后端：本地 CoreML（A.I. Duet / Performance RNN）"
        case .localRule:
            return backendStatusText ?? "后端：本地规则生成（无需电脑端服务）"
        }
    }

    private func backendTitle(_ kind: ImprovBackendKind) -> String {
        switch kind {
        case .networkBonjourHTTPAriaV2:
            "网络本地连接（Aria v2）"
        case .networkBonjourWebSocketAriaV2:
            "网络本地连接（Aria v2 Streaming）"
        case .localCoreMLDuet:
            "本地 CoreML（A.I. Duet / Performance RNN）"
        case .localRule:
            "本地 rule（无需模型/无需电脑端）"
        }
    }

    private func migrateLegacyBackendKindIfNeeded() {
        guard ImprovBackendKind(rawValue: improvBackendKindRawValue) == nil else { return }
        improvBackendKindRawValue = ImprovBackendSelection.defaultKind.rawValue
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
        isRecording: false,
        recordingElapsedText: "00:00",
        canStartRecording: true,
        onBackToLibrary: {},
        onStartRecording: {},
        onStopRecording: {},
        onOpenTakeLibrary: {},
        onRetryVirtualPianoPlacement: {},
        onRequestSessionRebuild: {},
        onDebugInjectAIImprovPhrase: {}
    )
}
