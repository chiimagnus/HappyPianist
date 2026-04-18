import SwiftUI
import UniformTypeIdentifiers
import simd

struct ContentView: View {
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel

    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("按步骤完成：校准 → 导入谱子 → AR 引导练习。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("AR 引导") {
                        Text(homeViewModel.immersiveStatusText)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("校准") {
                        Text(homeViewModel.calibrationStatusText)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("谱子") {
                        Text(homeViewModel.scoreStatusText)
                            .foregroundStyle(.secondary)
                    }

                    if let stepCountText = homeViewModel.stepCountText {
                        LabeledContent("步骤") {
                            Text(stepCountText)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("状态")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(homeViewModel.nextActionHint)
                        if let message = homeViewModel.calibrationStatusMessage {
                            Text(message)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("谱子") {
                    Text("导入 MusicXML 后会生成练习步骤。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let importErrorMessage = homeViewModel.importErrorMessage {
                        Text(importErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("导入 MusicXML…") {
                        homeViewModel.isImporterPresented = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(homeViewModel.canImportScore == false)
                    .hoverEffect()
                }
            }
            .navigationTitle("孤独钢琴家")
            .navigationBarTitleDisplayMode(.inline)
        }
        .buttonBorderShape(.roundedRectangle)
        .fileImporter(
            isPresented: $homeViewModel.isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            homeViewModel.handleImportResult(result)
        }
        .sheet(isPresented: arGuideSheetIsPresented) {
            ARGuideSheetView(viewModel: arGuideViewModel)
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            HomeOrnamentBar(viewModel: homeViewModel)
        }
    }

    private var arGuideSheetIsPresented: Binding<Bool> {
        Binding(
            get: { homeViewModel.immersiveSpaceState != .closed },
            set: { isPresented in
                guard isPresented == false else { return }
                homeViewModel.stopARGuide(using: dismissImmersiveSpace)
            }
        )
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
