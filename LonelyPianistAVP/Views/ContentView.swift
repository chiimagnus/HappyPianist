import SwiftUI
import UniformTypeIdentifiers
import simd

struct ContentView: View {
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel

    @State private var navigationPath: [MainFlowRoute] = []
    @ScaledMetric(relativeTo: .title) private var stepOrbSize: CGFloat = 200

    private enum MainFlowRoute: Hashable {
        case calibration
        case practice
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainFlowPanel
                .padding(18)
            .navigationTitle("孤独钢琴家")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: MainFlowRoute.self) { route in
                switch route {
                case .calibration:
                    CalibrationStepView(viewModel: arGuideViewModel)
                        .navigationTitle("Step 1 · 校准")
                case .practice:
                    PracticeStepView(viewModel: arGuideViewModel)
                        .navigationTitle("Step 2 · 开始练习")
                }
            }
            .toolbar {
                if navigationPath.isEmpty, homeViewModel.canImportScore {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("导入 MusicXML…") {
                            homeViewModel.isImporterPresented = true
                        }
                        .hoverEffect()
                    }
                }
            }
        }
        .buttonBorderShape(.roundedRectangle)
        .fileImporter(
            isPresented: $homeViewModel.isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            homeViewModel.handleImportResult(result)
        }
        .alert(
            "导入失败",
            isPresented: Binding(
                get: { homeViewModel.importErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        homeViewModel.clearImportError()
                    }
                }
            )
        ) {
            Button("好") {
                homeViewModel.clearImportError()
            }
        } message: {
            Text(homeViewModel.importErrorMessage ?? "未知错误")
        }
    }

    private var mainFlowPanel: some View {
        VStack {
            Spacer(minLength: 0)

            HStack(spacing: 18) {
                stepNode(
                    title: "校准",
                    stepLabel: "第一步",
                    isEnabled: true,
                    route: .calibration,
                    accent: .blue,
                    helpText: nil
                )

                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                stepNode(
                    title: "开始练习",
                    stepLabel: "第二步",
                    isEnabled: homeViewModel.canEnterPractice,
                    route: .practice,
                    accent: .green,
                    helpText: homeViewModel.canEnterPractice ? nil : "需要先完成校准并导入 MusicXML"
                )
                .opacity(homeViewModel.canEnterPractice ? 1.0 : 0.45)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func stepNode(
        title: String,
        stepLabel: String,
        isEnabled: Bool,
        route: MainFlowRoute,
        accent: Color,
        helpText: String?
    ) -> some View {
        let base = NavigationLink(value: route) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .overlay {
                            Circle()
                                .strokeBorder(accent.opacity(0.55), lineWidth: 2)
                        }

                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .padding(16)

                    if isEnabled == false {
                        VStack {
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 14)
                    }
                }
                .frame(width: stepOrbSize, height: stepOrbSize)

                Text(stepLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .disabled(isEnabled == false)

        if let helpText {
            base.help(helpText)
        } else {
            base
        }
    }
}

#Preview("主页 - 初始") {
    let appModel = AppModel()
    appModel.calibrationStatusMessage = "请重新校准"
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}

#Preview("主页 - 默认") {
    let appModel = AppModel()
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}

#Preview("主页 - 已校准") {
    let appModel = AppModel()
    appModel.calibration = PianoCalibration(
        a0: SIMD3<Float>(-0.7, 0.8, -1.0),
        c8: SIMD3<Float>(0.7, 0.8, -1.0),
        planeHeight: 0.8
    )
    appModel.calibrationStatusMessage = "已加载校准"
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}

#Preview("主页 - 已导入谱子") {
    let appModel = AppModel()
    appModel.calibration = PianoCalibration(
        a0: SIMD3<Float>(-0.7, 0.8, -1.0),
        c8: SIMD3<Float>(0.7, 0.8, -1.0),
        planeHeight: 0.8
    )
    appModel.setImportedSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: nil)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 64, staff: nil)])
        ],
        file: nil
    )
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}
