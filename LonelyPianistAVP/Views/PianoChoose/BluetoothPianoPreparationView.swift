import SwiftUI

struct BluetoothMIDIPreparationView: View {
    typealias PreviewScenario = BluetoothMIDIConnectionSection.PreviewScenario

    @Environment(AppRouter.self) private var router
    @Bindable var viewModel: ARGuideViewModel
    private let previewScenario: PreviewScenario?

    init(viewModel: ARGuideViewModel, previewScenario: PreviewScenario? = nil) {
        self.viewModel = viewModel
        self.previewScenario = previewScenario
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("真实钢琴（蓝牙 MIDI）")
                .font(.largeTitle.weight(.bold))

            BluetoothMIDIConnectionSection(previewScenario: previewScenario) { sourceCount in
                router.flowState.bluetoothMIDISourceCount = sourceCount
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
    }
}

#Preview("蓝牙 MIDI：已连接") {
    BluetoothMIDIPreparationViewPreviewHarness(scenario: .readyConnected)
}

#Preview("蓝牙 MIDI：无 Sources") {
    BluetoothMIDIPreparationViewPreviewHarness(scenario: .readyNoSources)
}

#Preview("蓝牙 MIDI：蓝牙关闭") {
    BluetoothMIDIPreparationViewPreviewHarness(scenario: .bluetoothPoweredOff)
}

#Preview("蓝牙 MIDI：未授权") {
    BluetoothMIDIPreparationViewPreviewHarness(scenario: .unauthorized)
}

#Preview("蓝牙 MIDI：检查中") {
    BluetoothMIDIPreparationViewPreviewHarness(scenario: .checking)
}

@MainActor
private struct BluetoothMIDIPreparationViewPreviewHarness: View {
    @State private var services = AppServices()
    @State private var flowState = FlowState()
    @State private var router: AppRouter
    @State private var viewModel: ARGuideViewModel
    private let scenario: BluetoothMIDIPreparationView.PreviewScenario

    init(scenario: BluetoothMIDIPreparationView.PreviewScenario) {
        self.scenario = scenario

        let services = AppServices()
        let flowState = FlowState()

        flowState.selectedPianoModeID = "bluetooth_midi"
        flowState.isCalibrationCompleted = true

        let router = AppRouter(flowState: flowState, pianoModeRegistry: services.pianoModeRegistry)
        let appState = AppState(
            arTrackingService: services.arTrackingService,
            calibrationCaptureService: services.calibrationCaptureService,
            calibrationRepository: services.calibrationRepository,
            keyGeometryService: services.keyGeometryService
        )

        _services = State(initialValue: services)
        _flowState = State(initialValue: flowState)
        _router = State(initialValue: router)
        _viewModel = State(initialValue: ARGuideViewModel(
            appState: appState,
            flowState: flowState,
            pianoModeRegistry: services.pianoModeRegistry,
            practiceSessionViewModelFactory: services.practiceSessionViewModelFactory
        ))
    }

    var body: some View {
        BluetoothMIDIPreparationView(viewModel: viewModel, previewScenario: scenario)
            .environment(router)
            .padding()
    }
}
