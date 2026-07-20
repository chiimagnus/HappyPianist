import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel
    let onPracticeFinished: () -> Void
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var isAudioErrorAlertPresented = false
    @State private var isAutoplayErrorAlertPresented = false
    @State private var isSessionReplacementErrorAlertPresented = false
    @State private var isRoundCompletionAlertPresented = false
    @State private var isTakeLibraryPresented = false
    @State private var isSettingsPresented = false
    @State private var practiceViewHeight: CGFloat = 640
    @State private var isAutoplayEnabled = false

    var body: some View {
        PracticeStepLayout(
            viewModel: viewModel,
            isTakeLibraryPresented: $isTakeLibraryPresented,
            isSettingsPresented: $isSettingsPresented,
            practiceViewHeight: $practiceViewHeight,
            isAutoplayEnabled: $isAutoplayEnabled,
            highlightByMIDINote: highlightByMIDINote,
            fingeringByMIDINote: fingeringByMIDINote
        )
        .modifier(
            PracticeStepStateSynchronizationModifier(
                viewModel: viewModel,
                isAutoplayEnabled: $isAutoplayEnabled,
                isSettingsPresented: $isSettingsPresented,
                isRoundCompletionAlertPresented: $isRoundCompletionAlertPresented,
                isAudioErrorAlertPresented: $isAudioErrorAlertPresented,
                isAutoplayErrorAlertPresented: $isAutoplayErrorAlertPresented,
                isSessionReplacementErrorAlertPresented: $isSessionReplacementErrorAlertPresented
            )
        )
        .modifier(
            PracticeStepAlertsModifier(
                viewModel: viewModel,
                isRoundCompletionAlertPresented: $isRoundCompletionAlertPresented,
                isAudioErrorAlertPresented: $isAudioErrorAlertPresented,
                isAutoplayErrorAlertPresented: $isAutoplayErrorAlertPresented,
                isSessionReplacementErrorAlertPresented: $isSessionReplacementErrorAlertPresented,
                roundSummary: roundSummary,
                onPracticeFinished: onPracticeFinished
            )
        )
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .sheet(isPresented: $isTakeLibraryPresented) {
            PracticeStepTakeLibrarySheet(
                viewModel: viewModel,
                isPresented: $isTakeLibraryPresented
            )
        }
    }

    private func handleAppear() {
        isStepVisible = true
        guard hasRequestedImmersiveOpen == false else { return }
        hasRequestedImmersiveOpen = true

        Task { @MainActor in
            let openHandler = makePracticeImmersiveOpenHandler(openImmersiveSpace)
            let dismissHandler = makePracticeImmersiveDismissHandler(dismissImmersiveSpace)
            viewModel.setPracticeVirtualPianoEnabled(isVirtualPianoMode)
            viewModel.setPracticeAutoplayEnabled(isAutoplayEnabled)
            await viewModel.enterPracticeStep(
                openImmersiveSpace: openHandler,
                dismissImmersiveSpace: dismissHandler
            )

            if isStepVisible == false {
                await viewModel.closeImmersiveForStep(dismissImmersiveSpace: dismissHandler)
                await viewModel.recoverImmersiveStateIfStuck()
            }
        }
    }

    private func handleDisappear() {
        viewModel.practiceFeedbackViewModel.cancel()
        viewModel.practiceSessionViewModel.setPracticeSettingsPresented(false)
        isStepVisible = false
        hasRequestedImmersiveOpen = false
    }

    private var isVirtualPianoMode: Bool {
        viewModel.isVirtualPianoMode
    }

    private var roundSummary: PracticeRoundSummaryViewModel? {
        let session = viewModel.practiceSessionViewModel
        guard session.state == .completed else { return nil }
        return PracticeRoundSummaryViewModel(
            progress: session.sessionProgress,
            configuration: session.activeRoundConfiguration,
            passageOccurrences: session.activeRange?.measureSpans.map(\.occurrenceID) ?? [],
            isFullPassage: session.activeRange?.measureSpans.count == session.measureSpans.count
        )
    }

    private var fingeringByMIDINote: [Int: String] {
        viewModel.practiceSessionViewModel.currentFingeringByMIDINote(isAutoplayEnabled: isAutoplayEnabled)
    }

    private var highlightByMIDINote: [Int: PianoKeyboard88Highlight] {
        let session = viewModel.practiceSessionViewModel
        guard let guide = session.currentPianoHighlightGuide else { return [:] }

        let resolver = PianoGuideKeyHighlightResolver()
        let highlightTokenByMidi = resolver.resolveHighlights(guide: guide)

        return Dictionary(uniqueKeysWithValues: highlightTokenByMidi.map { midiNote, token in
            let style = PianoGuideHighlightStyle.resolve(
                staffNumber: token.staffNumber,
                phase: token.phase,
                keyKind: PianoKeyboard88View.keyKind(for: midiNote)
            )
            return (midiNote, PianoKeyboard88Highlight(fill: .guide(style)))
        })
    }
}

private struct PracticeStepLayout: View {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var isTakeLibraryPresented: Bool
    @Binding var isSettingsPresented: Bool
    @Binding var practiceViewHeight: CGFloat
    @Binding var isAutoplayEnabled: Bool
    let highlightByMIDINote: [Int: PianoKeyboard88Highlight]
    let fingeringByMIDINote: [Int: String]

    var body: some View {
        PracticeStepMainContent(
            viewModel: viewModel,
            practiceViewHeight: $practiceViewHeight,
            highlightByMIDINote: highlightByMIDINote,
            fingeringByMIDINote: fingeringByMIDINote
        )
        .ornament(
            visibility: isSettingsPresented ? .visible : .hidden,
            attachmentAnchor: .scene(.trailing),
            contentAlignment: .leading
        ) {
            PracticeStepSettingsPanel(
                viewModel: viewModel,
                isTakeLibraryPresented: $isTakeLibraryPresented,
                practiceViewHeight: practiceViewHeight
            )
        }
        .toolbar {
            PracticeStepToolbar(
                viewModel: viewModel,
                isAutoplayEnabled: $isAutoplayEnabled,
                isSettingsPresented: $isSettingsPresented
            )
        }
    }
}

private struct PracticeStepMainContent: View {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var practiceViewHeight: CGFloat
    let highlightByMIDINote: [Int: PianoKeyboard88Highlight]
    let fingeringByMIDINote: [Int: String]

    var body: some View {
        let session = viewModel.practiceSessionViewModel

        VStack(spacing: 30) {
            GrandStaffNotationView(
                projection: session.notationProjection ?? .empty,
                overlay: session.activeNotationOverlay,
                measureSpans: session.notationMeasureSpans,
                context: session.currentGrandStaffNotationContext,
                practiceHandMode: session.practiceHandMode,
                scrollTickProvider: session.notationViewportTick
            )
            .frame(minHeight: 350, maxHeight: .infinity)

            PianoKeyboard88View(
                highlightByMIDINote: highlightByMIDINote,
                highlightOccurrenceID: session.currentPianoHighlightGuide?.id,
                fingeringByMIDINote: fingeringByMIDINote
            )
            .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
        }
        .containerRelativeFrame(.horizontal, count: 100, span: 95, spacing: 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
        .overlay(alignment: .top) {
            if let cue = viewModel.practiceFeedbackViewModel.cue {
                PracticeFeedbackCueView(event: cue)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            practiceViewHeight = height
        }
    }
}

private struct PracticeStepSettingsPanel: View {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var isTakeLibraryPresented: Bool
    let practiceViewHeight: CGFloat

    var body: some View {
        let session = viewModel.practiceSessionViewModel

        PracticeSettingsView(
            roundConfigurationController: session.roundConfigurationController,
            virtualPerformerEnabled: virtualPerformerEnabled,
            backendStatusText: viewModel.backendStatusText,
            lastImprovStatusText: viewModel.lastImprovStatusText,
            recordingSourceText: viewModel.recordingSourceText,
            isAIPerformanceActive: viewModel.isAIPerformanceActive,
            isVirtualPianoMode: viewModel.isVirtualPianoMode,
            isBluetoothMIDIMode: viewModel.isBluetoothMIDIMode,
            gazePlaneDiskStatusText: viewModel.gazePlaneDiskStatusText,
            isRecording: viewModel.isRecording,
            recordingElapsedText: viewModel.recordingElapsedText,
            canStartRecording: canStartRecording,
            onStartRecording: viewModel.startRecording,
            onStopRecording: viewModel.stopRecording,
            onOpenTakeLibrary: {
                isTakeLibraryPresented = true
            },
            onRetryVirtualPianoPlacement: viewModel.retryVirtualPianoPlacement,
            onApplyPendingConfiguration: applyPendingConfiguration,
            onDebugInjectAIImprovPhrase: debugInjectAIImprovPhrase,
            measureMap: measureMap
        )
        .frame(width: 400, height: practiceViewHeight)
        .glassBackgroundEffect()
    }

    private var virtualPerformerEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.aiPerformanceViewModel.isVirtualPerformerEnabled },
            set: { viewModel.setPracticeVirtualPerformerEnabled($0) }
        )
    }

    private var canStartRecording: Bool {
        viewModel.canRecord &&
            viewModel.isAIPerformanceActive == false &&
            viewModel.takePlaybackViewModel.isPlaying == false
    }

    private var measureMap: PracticeMeasureMapViewModel {
        let session = viewModel.practiceSessionViewModel
        return PracticeMeasureMapViewModel(
            measureSpans: session.measureSpans,
            progress: session.sessionProgress,
            handMode: session.practiceHandMode,
            currentPassage: session.activeRoundConfiguration?.passage,
            currentMeasure: session.measureIndex?.occurrenceID(forStepIndex: session.currentStepIndex)?.sourceMeasureID
        )
    }

    private func applyPendingConfiguration() {
        let requiresSessionRebuild = viewModel.practiceSessionViewModel.applyPendingRoundConfiguration()
        if requiresSessionRebuild {
            Task { await viewModel.replacePracticeSessionViewModel() }
        }
    }

    private func debugInjectAIImprovPhrase() {
        #if DEBUG
            viewModel.debugInjectAIImprovPhrase()
        #endif
    }
}

private struct PracticeStepToolbar: ToolbarContent {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var isAutoplayEnabled: Bool
    @Binding var isSettingsPresented: Bool

    var body: some ToolbarContent {
        let session = viewModel.practiceSessionViewModel
        let manualAdvanceMode = session.manualAdvanceMode

        ToolbarItemGroup(placement: .bottomOrnament) {
            if isAutoplayEnabled == false {
                Button(manualAdvanceMode.nextButtonTitle, systemImage: "forward.fill") {
                    viewModel.skipStep()
                }
                .disabled(
                    viewModel.isAIPerformanceActive ||
                        viewModel.hasImportedSteps == false ||
                        session.state == .completed
                )

                Button(manualAdvanceMode.replayButtonTitle, systemImage: "speaker.wave.2.fill") {
                    if manualAdvanceMode == .measure {
                        viewModel.replayCurrentPracticeUnit()
                    } else {
                        viewModel.playCurrentPracticeStepSound()
                    }
                }
                .disabled(
                    viewModel.isAIPerformanceActive ||
                        session.state == .ready ||
                        session.currentStep == nil
                )
            }

            Toggle("自动播放", isOn: $isAutoplayEnabled)
                .toggleStyle(.button)
                .disabled(viewModel.isAIPerformanceActive)

            Button("设置", systemImage: "gearshape") {
                isSettingsPresented.toggle()
            }

            Text("进度 \(viewModel.practiceProgressText)")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if viewModel.isVirtualPianoMode, let status = viewModel.gazePlaneDiskStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PracticeStepStateSynchronizationModifier: ViewModifier {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var isAutoplayEnabled: Bool
    @Binding var isSettingsPresented: Bool
    @Binding var isRoundCompletionAlertPresented: Bool
    @Binding var isAudioErrorAlertPresented: Bool
    @Binding var isAutoplayErrorAlertPresented: Bool
    @Binding var isSessionReplacementErrorAlertPresented: Bool

    func body(content: Content) -> some View {
        let session = viewModel.practiceSessionViewModel

        content
            .onChange(of: isAutoplayEnabled) {
                viewModel.setPracticeAutoplayEnabled(isAutoplayEnabled)
            }
            .onChange(of: isSettingsPresented) {
                session.setPracticeSettingsPresented(isSettingsPresented)
            }
            .onChange(of: session.latestFeedbackEvent) {
                viewModel.practiceFeedbackViewModel.present(session.latestFeedbackEvent)
            }
            .onChange(of: session.state, initial: true) { _, state in
                isRoundCompletionAlertPresented = state == .completed
            }
            .onChange(of: session.audioErrorMessage) {
                isAudioErrorAlertPresented = session.audioErrorMessage != nil
            }
            .onChange(of: session.autoplayErrorMessage) {
                isAutoplayErrorAlertPresented = session.autoplayErrorMessage != nil
            }
            .onChange(of: viewModel.practiceProgressSaveErrorMessage) {
                isSessionReplacementErrorAlertPresented = viewModel.practiceProgressSaveErrorMessage != nil
            }
    }
}

private struct PracticeStepAlertsModifier: ViewModifier {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var isRoundCompletionAlertPresented: Bool
    @Binding var isAudioErrorAlertPresented: Bool
    @Binding var isAutoplayErrorAlertPresented: Bool
    @Binding var isSessionReplacementErrorAlertPresented: Bool
    let roundSummary: PracticeRoundSummaryViewModel?
    let onPracticeFinished: () -> Void

    func body(content: Content) -> some View {
        let session = viewModel.practiceSessionViewModel

        content
            .alert(
                "这一轮练习完成",
                isPresented: $isRoundCompletionAlertPresented,
                presenting: roundSummary
            ) { summary in
                Button(summary.actionTitle) {
                    if session.perform(summary.nextAction) == false {
                        onPracticeFinished()
                    }
                }
                Button("返回曲库", action: onPracticeFinished)
            } message: { summary in
                Text(summary.detailText)
            }
            .alert("音频不可用", isPresented: $isAudioErrorAlertPresented) {
                Button("知道了") {
                    session.clearAudioError()
                }
            } message: {
                Text(session.audioErrorMessage ?? "")
            }
            .alert("无法自动播放", isPresented: $isAutoplayErrorAlertPresented) {
                Button("知道了") {
                    session.clearAutoplayError()
                }
            } message: {
                Text(session.autoplayErrorMessage ?? "")
            }
            .alert("练习进度尚未保存", isPresented: $isSessionReplacementErrorAlertPresented) {
                Button("知道了") {
                    viewModel.clearPracticeProgressSaveError()
                }
            } message: {
                Text(viewModel.practiceProgressSaveErrorMessage ?? "")
            }
    }
}

private struct PracticeStepTakeLibrarySheet: View {
    @Bindable var viewModel: ARGuideViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            TakeLibraryView(
                takes: viewModel.takeLibraryTakes,
                playbackViewModel: viewModel.takePlaybackViewModel,
                isRecording: viewModel.isRecording,
                errorMessage: viewModel.takeLibraryErrorMessage,
                onErrorDismiss: viewModel.dismissTakeLibraryError,
                onRename: viewModel.renameTake,
                onDelete: viewModel.deleteTake,
                onClearAll: viewModel.clearAllTakes,
                makeMIDIExport: viewModel.makeMIDIExport
            )
            .navigationTitle("录制库")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        isPresented = false
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

#Preview("Step 3") {
    let worldAnchorCalibrationStore = WorldAnchorCalibrationStore()
    let keyGeometryService = PianoKeyGeometryService()
    let arTrackingService = ARTrackingService()
    let calibrationCaptureService = CalibrationPointCaptureService()
    let calibrationRepository = CalibrationRepository(worldAnchorCalibrationStore: worldAnchorCalibrationStore)
    let pianoModeRegistry: PianoModeRegistryProtocol = PianoModeRegistryService(modes: [])
    let makePracticeSessionViewModel: @MainActor (String?) -> PracticeSessionViewModel = { _ in fatalError("preview only") }
    let practiceSetupState = PracticeSetupState()
    let appState = AppState(
        arTrackingService: arTrackingService,
        calibrationCaptureService: calibrationCaptureService,
        calibrationRepository: calibrationRepository,
        keyGeometryService: keyGeometryService
    )
    let viewModel = ARGuideViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        pianoModeRegistry: pianoModeRegistry,
        makePracticeSessionViewModel: makePracticeSessionViewModel
    )
    PracticeStepView(
        viewModel: viewModel,
        onPracticeFinished: {}
    )
}
