import SwiftUI
import UIKit

struct BluetoothMIDIPreparationView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var viewModel: ARGuideViewModel
    @State private var bluetoothAccessPreflight = BluetoothAccessPreflight()
    @State private var sourceConnectionViewModel = MIDISourceConnectionViewModel()
    @State private var bluetoothAccessStatus: BluetoothAccessPreflight.Status = .unknown
    @State private var didCheckBluetoothAccess = false
    @State private var centralViewReloadID = UUID()

    var body: some View {
        VStack(spacing: 20) {
            Text("真实钢琴（蓝牙 MIDI）准备")
                .font(.largeTitle.weight(.bold))

            GroupBox("第 0 步：连接蓝牙 MIDI") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("状态：\(sourceConnectionViewModel.statusText)")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let message = sourceConnectionViewModel.lastErrorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    switch bluetoothAccessStatus {
                        case .ready:
                            HStack(spacing: 10) {
                                Button("重载设备列表", systemImage: "arrow.clockwise") {
                                    centralViewReloadID = UUID()
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.roundedRectangle)
                                .hoverEffect()

                                Button("刷新 Sources", systemImage: "arrow.triangle.2.circlepath") {
                                    sourceConnectionViewModel.refreshSources()
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.roundedRectangle)
                                .hoverEffect()

                                Spacer()
                            }

                            BluetoothMIDICentralEmbeddedView()
                                .id(centralViewReloadID)
                                .frame(height: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            Text("已连接 Sources: \(sourceConnectionViewModel.sourceCount)")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            if sourceConnectionViewModel.sourceNames.isEmpty == false {
                                VStack(alignment: .leading, spacing: 6) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { router.exitToTypePicker(reason: "user exited from bluetooth midi preparation") }
            )

            HStack {
                Button("返回钢琴类型选择") {
                    router.exitToTypePicker(reason: "user tapped back from bluetooth midi preparation")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("下一步：去选曲") {
                    router.goToLibrary()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!router.canProceedToLibrary)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 700)
        .onChange(of: viewModel.calibrationPhase) {
            router.flowState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
        .onChange(of: sourceConnectionViewModel.connectionState) {
            router.flowState.bluetoothMIDISourceCount = sourceConnectionViewModel.sourceCount
        }
        .onAppear {
            sourceConnectionViewModel.start()
            router.flowState.bluetoothMIDISourceCount = sourceConnectionViewModel.sourceCount

            guard didCheckBluetoothAccess == false else { return }
            didCheckBluetoothAccess = true
            Task { @MainActor in
                await refreshBluetoothAccessStatus()
            }
        }
        .onDisappear {
            sourceConnectionViewModel.stop()
        }
    }

    private func refreshBluetoothAccessStatus() async {
        bluetoothAccessStatus = await bluetoothAccessPreflight.checkOrRequestAccess()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
                            await refreshBluetoothAccessStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()
                }

                if showsOpenSettingsButton {
                    Button("打开设置", systemImage: "gear") {
                        openAppSettings()
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
}
