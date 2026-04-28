import simd
import SwiftUI
import UniformTypeIdentifiers

enum MainFlowRoute: Hashable {
    case calibration
    case library
    case practice
}

struct ContentView: View {
    @Bindable var homeViewModel: HomeViewModel
    @Bindable var arGuideViewModel: ARGuideViewModel
    @Bindable var songLibraryViewModel: SongLibraryViewModel

    @State private var navigationPath: [MainFlowRoute] = []
    @ScaledMetric(relativeTo: .title) private var stepOrbSize: CGFloat = 250

    init(
        homeViewModel: HomeViewModel,
        arGuideViewModel: ARGuideViewModel,
        songLibraryViewModel: SongLibraryViewModel
    ) {
        self.homeViewModel = homeViewModel
        self.arGuideViewModel = arGuideViewModel
        self.songLibraryViewModel = songLibraryViewModel
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainFlowPanel
                .padding(18)
                .frame(minWidth: 560, idealWidth: 700)
                .navigationTitle("孤独钢琴家")
                .navigationDestination(for: MainFlowRoute.self) { route in
                    switch route {
                        case .calibration:
                            CalibrationStepView(viewModel: arGuideViewModel)
                                .frame(minWidth: 560, idealWidth: 700)
                                .navigationTitle("Step 1 · 校准")
                        case .library:
                            SongLibraryView(
                                viewModel: songLibraryViewModel,
                                navigationPath: $navigationPath
                            )
                            .frame(minWidth: 560, idealWidth: 700)
                            .navigationTitle("Step 2 · 选曲")
                        case .practice:
                            PracticeStepView(viewModel: arGuideViewModel)
                                .frame(minWidth: 920, idealWidth: 1200, minHeight: 320, idealHeight: 360)
                                .toolbar(.hidden, for: .navigationBar)
                    }
                }
        }
        .fileImporter(
            isPresented: $songLibraryViewModel.isMusicXMLImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                songLibraryViewModel.importMusicXML(from: urls)
            } catch {
                songLibraryViewModel.errorMessage = "导入失败：\(error.localizedDescription)"
            }
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
                title: "选曲",
                stepLabel: "第二步",
                isEnabled: true,
                route: .library,
                helpText: homeViewModel.practiceEntryHelpText,
                orbSize: stepOrbSize
            )

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
        arGuideViewModel: ARGuideViewModel(appModel: appModel),
        songLibraryViewModel: SongLibraryViewModel(appModel: appModel)
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
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 64, staff: nil)]),
        ],
        file: nil,
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    return ContentView(
        homeViewModel: HomeViewModel(appModel: appModel),
        arGuideViewModel: ARGuideViewModel(appModel: appModel),
        songLibraryViewModel: SongLibraryViewModel(appModel: appModel)
    )
}
