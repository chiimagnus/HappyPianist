import SwiftUI
import UniformTypeIdentifiers
import simd

fileprivate enum MainFlowRoute: Hashable {
    case calibration
    case practice
}

struct ContentView: View {
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel

    @State private var navigationPath: [MainFlowRoute] = []
    @ScaledMetric(relativeTo: .title) private var stepOrbSize: CGFloat = 250

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainFlowPanel
                .padding(18)
            .navigationTitle("孤独钢琴家")
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
                    }
                }
            }
        }
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
        HStack(alignment: .center) {
            Spacer()

            StepOrbLink(
                title: "校准",
                stepLabel: "第一步",
                isEnabled: true,
                route: .calibration,
                helpText: nil,
                orbSize: stepOrbSize
            )

            Spacer()

            Image(systemName: "arrow.right")

            Spacer()

            StepOrbLink(
                title: "开始练习",
                stepLabel: "第二步",
                isEnabled: homeViewModel.canEnterPractice,
                route: .practice,
                helpText: homeViewModel.canEnterPractice ? nil : "需要先完成校准并导入 MusicXML",
                orbSize: stepOrbSize
            )
            .opacity(homeViewModel.canEnterPractice ? 1.0 : 0.45)

            Spacer()
        }
    }
}

private struct StepOrbLink: View {
    let title: String
    let stepLabel: String
    let isEnabled: Bool
    let route: MainFlowRoute
    let helpText: String?
    let orbSize: CGFloat

    var body: some View {
        VStack(spacing: 10) {
            let base = NavigationLink(value: route) {
                ZStack {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .frame(width: orbSize, height: orbSize)

                    if isEnabled == false {
                        VStack {
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: orbSize, height: orbSize)
                        .padding(.bottom, 14)
                    }
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .disabled(isEnabled == false)

            if let helpText {
                base.help(helpText)
            } else {
                base
            }

            Text(stepLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("主页 - Step2 未解锁") {
    let appModel = AppModel()
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}

#Preview("主页 - Step2 已解锁") {
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

#Preview("主页 - 导入失败 Alert") {
    let appModel = AppModel()
    appModel.importErrorMessage = "导入失败：预览用错误"
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel)
    )
}
