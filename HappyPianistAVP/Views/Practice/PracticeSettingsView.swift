import SwiftUI

struct PracticeSettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case practice
        case improvDuet

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .practice:
                "练习"
            case .improvDuet:
                "即兴对弹"
            }
        }
    }

    @Bindable var roundConfigurationController: PracticeRoundConfigurationController
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
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onOpenTakeLibrary: () -> Void
    let onRetryVirtualPianoPlacement: () -> Void
    let onApplyPendingConfiguration: () -> Void
    let onDebugInjectAIImprovPhrase: () -> Void
    let measureMap: PracticeMeasureMapViewModel?

    @AppStorage("debugKeyboardAxesOverlayEnabled") private var debugKeyboardAxesOverlayEnabled = false
    @AppStorage(AudioOutputVolumeSettings.userDefaultsKey)
    private var audioOutputVolume = Double(AudioOutputVolumeSettings.defaultValue)
    @AppStorage(PracticeSessionSettingsKeys.improvBackendKind)
    private var improvBackendKindRawValue = ImprovBackendSelection.defaultKind.rawValue

    @State private var destinationConnectionViewModel = MIDIDestinationConnectionViewModel()
    @State private var isAdvancedFeaturesExpanded = false
    @State private var selectedTab: SettingsTab = .practice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("设置分类", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedTab {
                case .practice:
                    if let measureMap {
                        DisclosureGroup("小节恢复地图") {
                            PracticeMeasureMapView(viewModel: measureMap)
                        }
                    }
                    if isBluetoothMIDIMode {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("发声路由", selection: $roundConfigurationController.pendingSoundOutputRoute) {
                                ForEach(PracticeSoundOutputRoute.allCases) { route in
                                    Text(route.title).tag(route)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 12) {
                                Picker("MIDI 输出目的地", selection: $roundConfigurationController.pendingMIDIDestinationUniqueID) {
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
                            }

                            Toggle("Local Control Off（可选）", isOn: $roundConfigurationController.pendingSendLocalControlOff)

                            Text("发声路由将在下一轮生效；输出音量仍会立即生效。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)


                            if let message = destinationConnectionViewModel.lastErrorMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("练习", systemImage: "music.note")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Picker("练习手", selection: $roundConfigurationController.pendingHandMode) {
                            ForEach(PracticeHandMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("手动前进方式", selection: $roundConfigurationController.pendingManualAdvanceMode) {
                            ForEach(ManualAdvanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        LabeledContent("练习速度") {
                            Text(roundConfigurationController.pendingTempoScale, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                        }
                        Slider(
                            value: $roundConfigurationController.pendingTempoScale,
                            in: PracticeRoundConfiguration.supportedTempoRange,
                            step: 0.05
                        )

                        Toggle("循环当前片段", isOn: $roundConfigurationController.pendingLoopEnabled)

                        Stepper(
                            "连续成功 \(roundConfigurationController.pendingRequiredSuccesses) 次",
                            value: $roundConfigurationController.pendingRequiredSuccesses,
                            in: PracticeRoundConfiguration.supportedSuccessRange
                        )

                        Label("这些规则将在下一轮生效", systemImage: "arrow.clockwise")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("应用并重新开始本轮", systemImage: "arrow.clockwise") {
                            applyLocalControlOffIfNeeded()
                            onApplyPendingConfiguration()
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle)
                        .disabled(roundConfigurationController.hasPendingChanges == false)
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
                                if isRecording {
                                    Button("结束录制", systemImage: "stop.circle.fill") {
                                        onStopRecording()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .buttonBorderShape(.roundedRectangle)

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
                        }
                        .disabled(isAIPerformanceActive)
                    }

                case .improvDuet:
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

                                Text("用于 simulator：不依赖 Hand Tracking，直接触发 AI 生成/回放。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            #endif
                        }
                    }
                    .disabled(isAIPerformanceActive)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.automatic)
        .onAppear {
            if isBluetoothMIDIMode {
                destinationConnectionViewModel.start()
            }
        }
        .onDisappear {
            if isBluetoothMIDIMode {
                destinationConnectionViewModel.stop()
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func applyLocalControlOffIfNeeded() {
        let destinationID = roundConfigurationController.pendingMIDIDestinationUniqueID
        guard destinationID != 0 else { return }
        guard let destinationUniqueID = Int32(exactly: destinationID) else { return }
        destinationConnectionViewModel.sendLocalControlOff(
            roundConfigurationController.pendingSendLocalControlOff,
            destinationUniqueID: destinationUniqueID
        )
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

}

#Preview("练习设置") {
    let stateStore = PracticeSessionStateStore()
    let controller = PracticeRoundConfigurationController(
        stateStore: stateStore,
        settingsProvider: UserDefaultsPracticeSessionSettingsProvider()
    )
    PracticeSettingsView(
        roundConfigurationController: controller,
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
        onStartRecording: {},
        onStopRecording: {},
        onOpenTakeLibrary: {},
        onRetryVirtualPianoPlacement: {},
        onApplyPendingConfiguration: {},
        onDebugInjectAIImprovPhrase: {},
        measureMap: nil
    )
}
