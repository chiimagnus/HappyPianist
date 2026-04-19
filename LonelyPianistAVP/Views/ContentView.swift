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
    @ScaledMetric(relativeTo: .title) private var stepOrbSize: CGFloat = 200

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
                StepOrbLink(
                    title: "校准",
                    stepLabel: "第一步",
                    isEnabled: true,
                    route: .calibration,
                    accent: .blue,
                    helpText: nil,
                    orbSize: stepOrbSize
                )

                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                StepOrbLink(
                    title: "开始练习",
                    stepLabel: "第二步",
                    isEnabled: homeViewModel.canEnterPractice,
                    route: .practice,
                    accent: .green,
                    helpText: homeViewModel.canEnterPractice ? nil : "需要先完成校准并导入 MusicXML",
                    orbSize: stepOrbSize
                )
                .opacity(homeViewModel.canEnterPractice ? 1.0 : 0.45)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct StepOrbLink: View {
    let title: String
    let stepLabel: String
    let isEnabled: Bool
    let route: MainFlowRoute
    let accent: Color
    let helpText: String?
    let orbSize: CGFloat

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 10) {
            let base = NavigationLink(value: route) {
                orb
            }
            .buttonStyle(.plain)
            .buttonBorderShape(.circle)
            .contentShape(Circle())
            .containerShape(Circle())
            .hoverEffectDisabled(true)
            .disabled(isEnabled == false)
            .onHover { hovering in
                guard isEnabled else {
                    isHovering = false
                    return
                }
                isHovering = hovering
            }
            .animation(.easeInOut(duration: 0.18), value: isHovering)

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

    private var orb: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(accent.opacity(isHovering ? 0.85 : 0.55), lineWidth: isHovering ? 3 : 2)
                }
                .shadow(color: accent.opacity(isHovering ? 0.35 : 0.0), radius: isHovering ? 18 : 0)

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
        .frame(width: orbSize, height: orbSize)
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .contentShape(Circle())
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
