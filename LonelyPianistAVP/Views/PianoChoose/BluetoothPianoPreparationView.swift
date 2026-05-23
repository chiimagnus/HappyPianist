import CoreAudioKit
import SwiftUI

struct BluetoothMIDIPreparationView: View {
    @Environment(WindowTransitionState.self) private var windowState
    @Environment(\.preparationNavigationActions) private var navigationActions
    @Bindable var viewModel: ARGuideViewModel

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("返回钢琴类型选择") {
                    navigationActions.backToTypePicker()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("真实钢琴（蓝牙 MIDI）")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button("下一步：去选曲") {
                    navigationActions.nextToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceedToLibrary)
            }

            BluetoothMIDIConnectionSection { sourceCount in
                windowState.practiceSetupState.bluetoothMIDISourceCount = sourceCount
            }

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { windowState.resetToPreparation(reason: "user exited from bluetooth midi preparation") }
            )
        }
        .padding(24)
        .frame(minWidth: 600, idealWidth: 700)
        .onChange(of: viewModel.calibrationPhase) {
            windowState.practiceSetupState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
    }

    private var canProceedToLibrary: Bool {
        windowState.pianoModeRegistry
            .mode(for: windowState.practiceSetupState.selectedPianoModeID)?
            .canProceedToLibrary(context: PianoModeReadinessContext(practiceSetupState: windowState.practiceSetupState)) ?? false
    }
}

struct BluetoothMIDIConnectionSection: View {
    @Environment(\.openURL) private var openURL

    let onSourceCountChange: @MainActor (Int) -> Void

    @State private var bluetoothAccessViewModel = BluetoothAccessViewModel()
    @State private var sourceConnectionViewModel = MIDISourceConnectionViewModel()
    @State private var destinationConnectionViewModel = MIDIDestinationConnectionViewModel()
    @State private var centralViewReloadID = UUID()
    @State private var isDiagnosticsExpanded = false
    @State private var isDevicePickerPresented = false

    @AppStorage(PracticeSessionSettingsKeys.soundOutputRoute)
    private var soundOutputRouteRawValue = PracticeSoundOutputRoute.localSampler.rawValue
    @AppStorage(PracticeSessionSettingsKeys.midiDestinationUniqueID)
    private var midiDestinationUniqueID = 0
    @AppStorage(PracticeSessionSettingsKeys.sendLocalControlOff)
    private var sendLocalControlOff = false

    init(
        onSourceCountChange: @escaping @MainActor (Int) -> Void
    ) {
        self.onSourceCountChange = onSourceCountChange
    }

    var body: some View {
        VStack {
            switch bluetoothAccessViewModel.status {
                case .ready:
                    HStack(spacing: 12) {
                        Text("蓝牙 MIDI 设备")
                            .font(.headline)

                        Spacer()

                        Button("选择/连接…", systemImage: "dot.radiowaves.left.and.right") {
                            isDevicePickerPresented = true
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .popover(isPresented: $isDevicePickerPresented) {
                            VStack(alignment: .leading) {
                                Button {
                                    isDevicePickerPresented = false
                                } label: {
                                    Image(systemName: "xmark")
                                }

                                CentralViewControllerRepresentable()
                                    .id(centralViewReloadID)
                            }
                            .padding(16)
                            .frame(minWidth: 400, minHeight: 320)
                        }
                    }

                    HStack(spacing: 12) {
                        LabeledContent("MIDI 输入（CoreMIDI）") {
                            Text("\(sourceConnectionViewModel.sourceCount)")
                                .monospacedDigit()
                        }
                        .font(.callout)

                        Spacer()
                    }

                    Divider()

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

                        Text("若选择“仅 AVP 发声”，你可以在钢琴上手动关闭本地音量；或勾选此项让 AVP best-effort 向钢琴发送 Local Control Off（兼容性不保证）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let message = destinationConnectionViewModel.lastErrorMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    DisclosureGroup("诊断信息", isExpanded: $isDiagnosticsExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let message = sourceConnectionViewModel.lastErrorMessage {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Button("重载设备列表", systemImage: "arrow.clockwise") {
                                    centralViewReloadID = UUID()
                                }
                                .buttonBorderShape(.roundedRectangle)

                                Button("刷新 MIDI 输入", systemImage: "arrow.clockwise") {
                                    sourceConnectionViewModel.refreshSources()
                                }
                                .buttonBorderShape(.roundedRectangle)

                                Spacer()
                            }

                            LabeledContent("状态") {
                                Text(sourceConnectionViewModel.statusText)
                                    .monospaced()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if sourceConnectionViewModel.sourceNames.isEmpty {
                                Text("未发现任何 MIDI 输入。若你已在上方列表点了连接但这里仍为 0，可展开「诊断信息」点「刷新 MIDI 输入」，或点「重载设备列表」。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sources:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(sourceConnectionViewModel.sourceNames, id: \.self) { name in
                                        Text("• \(name)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout)

                case .bluetoothPoweredOff:
                    accessStatusCard(
                        title: "蓝牙已关闭",
                        message: "请在系统设置中打开蓝牙后重试。"
                    )

                case .unauthorized:
                    accessStatusCard(
                        title: "需要蓝牙权限",
                        message: "请在系统设置中允许 LonelyPianist 使用蓝牙，以便连接蓝牙 MIDI 钢琴。",
                        showsOpenSettingsButton: true
                    )

                case .unsupported:
                    accessStatusCard(
                        title: "不支持蓝牙 MIDI",
                        message: "当前设备或系统不支持 MIDI over Bluetooth。"
                    )

                case .unknown:
                    accessStatusCard(
                        title: "正在检查蓝牙状态…",
                        message: "若长时间无响应，请重试；若仍失败，请检查蓝牙开关与权限设置。",
                        showsRetryButton: true
                    )
            }
        }
        .onChange(of: sourceConnectionViewModel.connectionState) {
            onSourceCountChange(sourceConnectionViewModel.sourceCount)
        }
        .onChange(of: isDevicePickerPresented) {
            guard isDevicePickerPresented == false else { return }
            sourceConnectionViewModel.refreshSources()
        }
        .onAppear {
            sourceConnectionViewModel.start()
            destinationConnectionViewModel.start()
            onSourceCountChange(sourceConnectionViewModel.sourceCount)

            Task { @MainActor in
                await bluetoothAccessViewModel.refreshStatus()
            }
        }
        .onDisappear {
            sourceConnectionViewModel.stop()
            destinationConnectionViewModel.stop()
        }
        .onChange(of: sendLocalControlOff) {
            applyLocalControlOffIfNeeded()
        }
        .onChange(of: midiDestinationUniqueID) {
            applyLocalControlOffIfNeeded()
        }
    }

    private func applyLocalControlOffIfNeeded() {
        guard midiDestinationUniqueID != 0 else { return }
        guard let destinationUniqueID = Int32(exactly: midiDestinationUniqueID) else { return }
        destinationConnectionViewModel.sendLocalControlOff(sendLocalControlOff, destinationUniqueID: destinationUniqueID)
    }

    private func accessStatusCard(
        title: String,
        message: String,
        showsRetryButton: Bool = false,
        showsOpenSettingsButton: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if showsRetryButton {
                    Button("重试", systemImage: "arrow.clockwise") {
                        Task { @MainActor in
                            await bluetoothAccessViewModel.refreshStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()
                }

                if showsOpenSettingsButton {
                    Button("打开设置", systemImage: "gear") {
                        if let settingsURL = bluetoothAccessViewModel.appSettingsURL {
                            openURL(settingsURL)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct CentralViewControllerRepresentable: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> UINavigationController {
            let centralViewController = CABTMIDICentralViewController()
            centralViewController.title = nil

            let navigationController = UINavigationController(rootViewController: centralViewController)
            navigationController.setNavigationBarHidden(true, animated: false)
            return navigationController
        }

        func updateUIViewController(_: UINavigationController, context _: Context) {}
    }
}
