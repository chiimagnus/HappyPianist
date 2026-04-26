import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var isLocalizationPopoverPresented = false
    @State private var isSettingsPopoverPresented = false
    @State private var isAudioErrorAlertPresented = false

    @AppStorage("practiceStep3AutoplayEnabled") private var isAutoplayEnabled = false
    @AppStorage("practiceAudioRecognitionDebugOverlayEnabled") private var isAudioDebugOverlayEnabled = false
    @AppStorage("practiceAudioRecognitionEnabled") private var isAudioRecognitionEnabled = true
    @AppStorage("practiceStep3AudioRecognitionMode") private var step3AudioRecognitionMode = Step3AudioRecognitionMode.lowLatency.rawValue

    var body: some View {
        PianoKeyboard88View(highlightedMIDINotes: highlightedMIDINotes, fingeringByMIDINote: fingeringByMIDINote)
            .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
            .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 18)
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Step3WindowGeometryHint()
                        .frame(width: 0, height: 0)
                    if isAudioDebugOverlayEnabled {
                        Step3AudioDebugOverlay(
                            sessionViewModel: viewModel.practiceSessionViewModel,
                            isAutoplayEnabled: isAutoplayEnabled
                        )
                        .padding(12)
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomOrnament) {
                    Button("返回", systemImage: "chevron.backward") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()

                    if isAutoplayEnabled == false {
                        Button("下一步", systemImage: "forward.fill") {
                            viewModel.skipStep()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(viewModel.hasImportedSteps == false || viewModel.practiceSessionViewModel
                            .state == .completed)

                        Button("播放琴声", systemImage: "speaker.wave.2.fill") {
                            viewModel.playCurrentPracticeStepSound()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(viewModel.practiceSessionViewModel.currentStep == nil)
                    }

                    Toggle("自动播放", isOn: $isAutoplayEnabled)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()

                    Button("设置", systemImage: "gearshape") {
                        isSettingsPopoverPresented.toggle()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()
                    .popover(isPresented: $isSettingsPopoverPresented) {
                        PracticeSettingsView()
                    }

                    if isAutoplayEnabled {
                        Text(viewModel.practiceSessionViewModel.isSustainPedalDown ? "Pedal ↓" : "Pedal ↑")
                            .foregroundStyle(.secondary)
                    }

                    Text("进度 \(viewModel.practiceProgressText)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if isAutoplayEnabled == false {
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
            }
            .buttonBorderShape(.roundedRectangle)
            .onAppear {
                isStepVisible = true
                guard hasRequestedImmersiveOpen == false else { return }
                hasRequestedImmersiveOpen = true

                Task { @MainActor in
                    viewModel.practiceSessionViewModel.refreshAudioRecognitionFromSettings()
                    viewModel.setPracticeAutoplayEnabled(isAutoplayEnabled)
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
            .onChange(of: isAutoplayEnabled) {
                viewModel.setPracticeAutoplayEnabled(isAutoplayEnabled)
            }
            .onChange(of: isAudioRecognitionEnabled) {
                viewModel.practiceSessionViewModel.refreshAudioRecognitionFromSettings()
            }
            .onChange(of: step3AudioRecognitionMode) {
                viewModel.practiceSessionViewModel.refreshAudioRecognitionFromSettings()
            }
            .onChange(of: viewModel.practiceSessionViewModel.audioErrorMessage) {
                isAudioErrorAlertPresented = viewModel.practiceSessionViewModel.audioErrorMessage != nil
            }
            .alert("音频不可用", isPresented: $isAudioErrorAlertPresented) {
                Button("知道了") {
                    viewModel.practiceSessionViewModel.clearAudioError()
                }
            } message: {
                Text(viewModel.practiceSessionViewModel.audioErrorMessage ?? "")
            }
            .onDisappear {
                isStepVisible = false
                hasRequestedImmersiveOpen = false
                viewModel.setPracticeAutoplayEnabled(false)
                viewModel.resetPracticeLocalizationState()
                Task { @MainActor in
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
            }
    }

    private var highlightedMIDINotes: Set<Int> {
        if isAutoplayEnabled {
            return viewModel.practiceSessionViewModel.autoplayHighlightedMIDINotes
        }
        guard let currentStep = viewModel.practiceSessionViewModel.currentStep else {
            return []
        }
        return Set(currentStep.notes.map(\.midiNote))
    }

    private var fingeringByMIDINote: [Int: String] {
        guard isAutoplayEnabled else { return [:] }
        guard let currentStep = viewModel.practiceSessionViewModel.currentStep else { return [:] }
        let items = currentStep.notes.compactMap { note -> (Int, String)? in
            guard let text = note.fingeringText, text.isEmpty == false else { return nil }
            return (note.midiNote, text)
        }
        return Dictionary(uniqueKeysWithValues: items)
    }

    private var localizationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.practiceLocalizationStatusText ?? "进入后会自动定位钢琴。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Text(viewModel.step3ARStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.step3HandAssistStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(viewModel.step3AudioStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("提示：即使定位失败或环境不支持，你也可以直接使用下方 2D 键盘的“下一步”继续练习。")
                .font(.caption)
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
    func makeUIViewController(context _: Context) -> UIViewController {
        WindowGeometryHintViewController()
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}

private final class WindowGeometryHintViewController: UIViewController {
    private var hasRequestedGeometryUpdate = false
    private var hasRequestedRestoreGeometryUpdate = false
    private var previousWindowSize: CGSize?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        capturePreviousWindowSizeIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestGeometryUpdateIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        requestRestoreGeometryUpdateIfNeeded()
    }

    private func requestGeometryUpdateIfNeeded() {
        guard hasRequestedGeometryUpdate == false else { return }
        guard let windowScene = view.window?.windowScene else { return }

        hasRequestedGeometryUpdate = true
        capturePreviousWindowSizeIfNeeded()

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

    private func requestRestoreGeometryUpdateIfNeeded() {
        guard hasRequestedRestoreGeometryUpdate == false else { return }
        guard let windowScene = view.window?.windowScene else { return }

        hasRequestedRestoreGeometryUpdate = true
        let restoreSize = previousWindowSize ?? CGSize(width: 700, height: 700)

        let preferences = UIWindowScene.GeometryPreferences.Vision(
            size: restoreSize,
            minimumSize: CGSize(width: 560, height: 560),
            maximumSize: nil,
            resizingRestrictions: nil
        )

        windowScene.requestGeometryUpdate(preferences) { error in
            print("Step 3 restore requestGeometryUpdate failed: \(error.localizedDescription)")
        }
    }

    private func capturePreviousWindowSizeIfNeeded() {
        guard previousWindowSize == nil else { return }
        guard let window = view.window else { return }
        let size = window.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        previousWindowSize = size
    }
}

#Preview("Step 3") {
    PracticeStepView(viewModel: ARGuideViewModel(appModel: AppModel()))
}
