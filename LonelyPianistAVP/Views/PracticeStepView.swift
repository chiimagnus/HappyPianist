import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var isLocalizationPopoverPresented = false

    var body: some View {
        PianoKeyboard88View(highlightedMIDINotes: highlightedMIDINotes)
            .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
            .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 18)
            .overlay {
                Step3WindowGeometryHint()
                    .frame(width: 0, height: 0)
            }
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                Button("返回", systemImage: "chevron.backward") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()

                Button("跳过", systemImage: "forward.fill") {
                    viewModel.skipStep()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(viewModel.canControlPractice == false)

                Text("进度 \(viewModel.practiceProgressText)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button("定位", systemImage: "scope") {
                    isLocalizationPopoverPresented.toggle()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .popover(isPresented: $isLocalizationPopoverPresented) {
                    localizationPopover
                }
            }
        }
        .buttonBorderShape(.roundedRectangle)
        .onAppear {
            isStepVisible = true
            guard hasRequestedImmersiveOpen == false else { return }
            hasRequestedImmersiveOpen = true

            Task { @MainActor in
                await viewModel.enterPracticeStep(
                    using: openImmersiveSpace,
                    dismissImmersiveSpace: dismissImmersiveSpace
                )

                if isStepVisible == false {
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
            }
        }
        .onDisappear {
            isStepVisible = false
            hasRequestedImmersiveOpen = false
            viewModel.resetPracticeLocalizationState()
            Task { @MainActor in
                await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                await viewModel.recoverImmersiveStateIfStuck()
            }
        }
    }

    private var highlightedMIDINotes: Set<Int> {
        guard let currentStep = viewModel.practiceSessionViewModel.currentStep else {
            return []
        }
        return Set(currentStep.notes.map(\.midiNote))
    }

    @ViewBuilder
    private var localizationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.practiceLocalizationStatusText ?? "进入后会自动定位钢琴。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if viewModel.canRetryPracticeLocalization {
                Button("重试定位", systemImage: "arrow.clockwise") {
                    Task { @MainActor in
                        await viewModel.retryPracticeLocalization(
                            using: openImmersiveSpace,
                            dismissImmersiveSpace: dismissImmersiveSpace
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
            }

            if viewModel.shouldSuggestCalibrationStep {
                Text("若持续失败，请返回主页进入 Step 1 重新校准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("返回主页", systemImage: "house") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
            }
        }
        .padding(16)
        .frame(minWidth: 320)
    }
}

private struct Step3WindowGeometryHint: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        WindowGeometryHintViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class WindowGeometryHintViewController: UIViewController {
    private var hasRequestedGeometryUpdate = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestGeometryUpdateIfNeeded()
    }

    private func requestGeometryUpdateIfNeeded() {
        guard hasRequestedGeometryUpdate == false else { return }
        guard let windowScene = view.window?.windowScene else { return }

        hasRequestedGeometryUpdate = true

        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: CGSize(width: 1600, height: 400),
            minimumSize: CGSize(width: 1200, height: 320),
            maximumSize: nil,
            resizingRestrictions: nil
        )

        windowScene.requestGeometryUpdate(preferences) { error in
            print("Step 3 requestGeometryUpdate failed: \(error.localizedDescription)")
        }
    }
}

#Preview("Step 3") {
    PracticeStepView(viewModel: ARGuideViewModel(appModel: AppModel()))
}
