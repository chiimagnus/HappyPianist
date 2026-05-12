import SwiftUI
import UIKit

struct RealPianoPreparationView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var viewModel: ARGuideViewModel
    @State private var isBluetoothMIDIPanelPresented = false
    @State private var bluetoothAccessPreflight = BluetoothAccessPreflight()
    @State private var bluetoothMIDIAlert: BluetoothMIDIAlert?
    @State private var midiDebugViewModel = BluetoothMIDIDebugViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("真实钢琴准备")
                .font(.largeTitle.weight(.bold))

            CalibrationStepView(
                viewModel: viewModel,
                onExit: { router.exitToTypePicker(reason: "user exited from real preparation") }
            )

            Button("Bluetooth MIDI…") {
                Task { @MainActor in
                    await openBluetoothMIDIPanel()
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle)
            .hoverEffect()

            GroupBox("MIDI 调试") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("状态：\(midiDebugViewModel.statusText)")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("刷新 Sources", systemImage: "arrow.clockwise") {
                            midiDebugViewModel.refreshSources()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                    }

                    Text("Sources: \(midiDebugViewModel.sourceNames.count)")
                        .font(.headline)

                    if midiDebugViewModel.sourceNames.isEmpty {
                        Text("未发现 MIDI sources。连接蓝牙 MIDI 后可在这里确认是否已出现在系统 MIDI 列表中。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(midiDebugViewModel.sourceNames, id: \.self) { name in
                                Text("• \(name)")
                                    .font(.callout)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Text("noteOn \(midiDebugViewModel.noteOnCount) / noteOff \(midiDebugViewModel.noteOffCount)")
                            .font(.callout)

                        if let last = midiDebugViewModel.lastNoteText {
                            Text("last: \(last)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("返回钢琴类型选择") {
                    router.exitToTypePicker(reason: "user tapped back from real preparation")
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
        .sheet(isPresented: $isBluetoothMIDIPanelPresented) {
            BluetoothMIDICentralView(isPresented: $isBluetoothMIDIPanelPresented)
        }
        .alert(item: $bluetoothMIDIAlert) { alert in
            switch alert {
                case .bluetoothPoweredOff:
                    Alert(
                        title: Text("蓝牙已关闭"),
                        message: Text("请在系统设置中打开蓝牙后重试。"),
                        dismissButton: .default(Text("好"))
                    )
                case .unauthorized:
                    Alert(
                        title: Text("需要蓝牙权限"),
                        message: Text("请在系统设置中允许 LonelyPianist 使用蓝牙，以便连接蓝牙 MIDI 钢琴。"),
                        primaryButton: .default(Text("打开设置"), action: openAppSettings),
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .unsupported:
                    Alert(
                        title: Text("不支持蓝牙 MIDI"),
                        message: Text("当前设备或系统不支持 MIDI over Bluetooth。"),
                        dismissButton: .default(Text("好"))
                    )
                case .unknown:
                    Alert(
                        title: Text("蓝牙状态未知"),
                        message: Text("请稍后再试；若仍失败，请检查蓝牙开关与权限设置。"),
                        dismissButton: .default(Text("好"))
                    )
            }
        }
        .onChange(of: viewModel.calibrationPhase) {
            router.flowState.isCalibrationCompleted = (viewModel.calibrationPhase == .completed)
        }
        .onAppear {
            midiDebugViewModel.start()
        }
        .onDisappear {
            midiDebugViewModel.stop()
        }
    }

    private func openBluetoothMIDIPanel() async {
        let status = await bluetoothAccessPreflight.checkOrRequestAccess()
        switch status {
            case .ready:
                isBluetoothMIDIPanelPresented = true
            case .bluetoothPoweredOff:
                bluetoothMIDIAlert = .bluetoothPoweredOff
            case .unauthorized:
                bluetoothMIDIAlert = .unauthorized
            case .unsupported:
                bluetoothMIDIAlert = .unsupported
            case .unknown:
                bluetoothMIDIAlert = .unknown
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum BluetoothMIDIAlert: String, Identifiable {
    case bluetoothPoweredOff
    case unauthorized
    case unsupported
    case unknown

    var id: String { rawValue }
}
