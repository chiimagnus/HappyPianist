import CoreAudioKit
import SwiftUI
import UIKit

struct BluetoothMIDIConnectionSection: View {
    enum PreviewScenario: Equatable {
        case readyConnected
        case readyNoSources
        case bluetoothPoweredOff
        case unauthorized
        case checking
    }

    let onSourceCountChange: @MainActor (Int) -> Void
    let previewScenario: PreviewScenario?

    @State private var bluetoothAccessPreflight = BluetoothAccessPreflight()
    @State private var sourceConnectionViewModel = MIDISourceConnectionViewModel()
    @State private var bluetoothAccessStatus: BluetoothAccessPreflight.Status = .unknown
    @State private var didCheckBluetoothAccess = false
    @State private var centralViewReloadID = UUID()
    @State private var isDiagnosticsExpanded = false

    private let isRunningInPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    init(
        previewScenario: PreviewScenario? = nil,
        onSourceCountChange: @escaping @MainActor (Int) -> Void
    ) {
        self.previewScenario = previewScenario
        self.onSourceCountChange = onSourceCountChange
    }

    var body: some View {
        VStack {
            switch bluetoothAccessStatus {
                case .ready:
                    CentralViewControllerRepresentable()
                        .id(centralViewReloadID)

                    HStack(spacing: 12) {
                        LabeledContent("MIDI 输入（CoreMIDI）") {
                            Text("\(sourceConnectionViewModel.sourceCount)")
                                .monospacedDigit()
                        }
                        .font(.callout)

                        Spacer()

                        Button("刷新", systemImage: "arrow.clockwise") {
                            sourceConnectionViewModel.refreshSources()
                        }
                            .buttonBorderShape(.roundedRectangle)
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

                                Spacer()
                            }

                            LabeledContent("状态") {
                                Text(sourceConnectionViewModel.statusText)
                                    .monospaced()
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if sourceConnectionViewModel.sourceNames.isEmpty {
                                Text("未发现任何 MIDI 输入。若你已在上方列表点了连接但这里仍为 0，可多点几次「刷新」。")
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
        .onAppear {
            if isRunningInPreviews {
                applyPreviewScenario(previewScenario ?? .readyConnected)
                onSourceCountChange(sourceConnectionViewModel.sourceCount)
                return
            }

            sourceConnectionViewModel.start()
            onSourceCountChange(sourceConnectionViewModel.sourceCount)

            guard didCheckBluetoothAccess == false else { return }
            didCheckBluetoothAccess = true
            Task { @MainActor in
                await refreshBluetoothAccessStatus()
            }
        }
        .onDisappear {
            guard isRunningInPreviews == false else { return }
            sourceConnectionViewModel.stop()
        }
    }

    private func applyPreviewScenario(_ scenario: PreviewScenario) {
        didCheckBluetoothAccess = true

        switch scenario {
            case .readyConnected:
                bluetoothAccessStatus = .ready
                sourceConnectionViewModel.connectionState = .connected(sourceCount: 1)
                sourceConnectionViewModel.sourceNames = ["FP-30X MIDI"]

            case .readyNoSources:
                bluetoothAccessStatus = .ready
                sourceConnectionViewModel.connectionState = .connected(sourceCount: 0)
                sourceConnectionViewModel.sourceNames = []
                sourceConnectionViewModel.lastErrorMessage = "Connect sources failed: -1"
                isDiagnosticsExpanded = true

            case .bluetoothPoweredOff:
                bluetoothAccessStatus = .bluetoothPoweredOff
                sourceConnectionViewModel.connectionState = .idle
                sourceConnectionViewModel.sourceNames = []

            case .unauthorized:
                bluetoothAccessStatus = .unauthorized
                sourceConnectionViewModel.connectionState = .idle
                sourceConnectionViewModel.sourceNames = []

            case .checking:
                bluetoothAccessStatus = .unknown
                sourceConnectionViewModel.connectionState = .idle
                sourceConnectionViewModel.sourceNames = []
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

#Preview("连接：已连接") {
    BluetoothMIDIConnectionSection(previewScenario: .readyConnected) { _ in }
        .padding()
        .frame(width: 720)
}

#Preview("连接：无 Sources") {
    BluetoothMIDIConnectionSection(previewScenario: .readyNoSources) { _ in }
        .padding()
        .frame(width: 720)
}

#Preview("连接：蓝牙关闭") {
    BluetoothMIDIConnectionSection(previewScenario: .bluetoothPoweredOff) { _ in }
        .padding()
        .frame(width: 720)
}

#Preview("连接：未授权") {
    BluetoothMIDIConnectionSection(previewScenario: .unauthorized) { _ in }
        .padding()
        .frame(width: 720)
}

#Preview("连接：检查中") {
    BluetoothMIDIConnectionSection(previewScenario: .checking) { _ in }
        .padding()
        .frame(width: 720)
}
