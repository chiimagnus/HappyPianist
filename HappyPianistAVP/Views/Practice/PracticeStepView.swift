import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel
    let onBackToLibrary: () -> Void
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var isAudioErrorAlertPresented = false
    @State private var isAutoplayErrorAlertPresented = false
    @State private var isSessionReplacementErrorAlertPresented = false
    @State private var isTakeLibraryPresented = false
    @State private var isSettingsPresented = false
    @State private var practiceViewHeight: CGFloat = 640
    @State private var isAutoplayEnabled = false

    var body: some View {
        let session = viewModel.practiceSessionViewModel
        let currentGuide = session.currentPianoHighlightGuide
        let practiceHandMode = session.practiceHandMode
        let manualAdvanceMode = session.manualAdvanceMode

        VStack(spacing: 30) {
            GrandStaffNotationView(
                guides: session.activeHighlightGuides,
                currentGuide: currentGuide,
                measureSpans: session.notationMeasureSpans,
                context: session.currentGrandStaffNotationContext,
                practiceHandMode: practiceHandMode,
                scrollTickProvider: session.autoplayState == .playing ? {
                    session.smoothNotationScrollTick()
                } : nil
            )
            .frame(height: 350)

            PianoKeyboard88View(
                highlightByMIDINote: highlightByMIDINote,
                highlightOccurrenceID: currentGuide?.id,
                fingeringByMIDINote: fingeringByMIDINote
            )
            .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)

            if session.state == .completed,
               let summary = PracticeRoundSummaryViewModel(
                   progress: session.sessionProgress,
                   configuration: session.activeRoundConfiguration,
                   passageOccurrences: session.activeRange?.measureSpans.map(\.occurrenceID) ?? [],
                   isFullPassage: session.activeRange?.measureSpans.count == session.measureSpans.count
               )
            {
                PracticeRoundSummaryView(
                    summary: summary,
                    onPrimaryAction: {
                        if session.perform(summary.nextAction) == false { onBackToLibrary() }
                    },
                    onContinue: { onBackToLibrary() }
                )
            }
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
        .ornament(
            visibility: isSettingsPresented ? .visible : .hidden,
            attachmentAnchor: .scene(.trailing),
            contentAlignment: .leading
        ) {
            PracticeSettingsView(
                roundConfigurationController: session.roundConfigurationController,
                virtualPerformerEnabled: virtualPerformerEnabled,
                backendStatusText: viewModel.backendStatusText,
                lastImprovStatusText: viewModel.lastImprovStatusText,
                recordingSourceText: viewModel.recordingSourceText,
                isAIPerformanceActive: viewModel.isAIPerformanceActive,
                isVirtualPianoMode: isVirtualPianoMode,
                isBluetoothMIDIMode: viewModel.isBluetoothMIDIMode,
                gazePlaneDiskStatusText: viewModel.gazePlaneDiskStatusText,
                isRecording: viewModel.isRecording,
                recordingElapsedText: viewModel.recordingElapsedText,
                canStartRecording: viewModel.canRecord && viewModel.isAIPerformanceActive == false && viewModel.takePlaybackViewModel.isPlaying == false,
                onStartRecording: {
                    viewModel.startRecording()
                },
                onStopRecording: {
                    viewModel.stopRecording()
                },
                onOpenTakeLibrary: {
                    isTakeLibraryPresented = true
                },
                onRetryVirtualPianoPlacement: {
                    viewModel.retryVirtualPianoPlacement()
                },
                onApplyPendingConfiguration: {
                    let requiresSessionRebuild = session.applyPendingRoundConfiguration()
                    if requiresSessionRebuild {
                        Task { await viewModel.replacePracticeSessionViewModel() }
                    }
                },
                onDebugInjectAIImprovPhrase: {
                    #if DEBUG
                        viewModel.debugInjectAIImprovPhrase()
                    #endif
                },
                measureMap: PracticeMeasureMapViewModel(
                    measureSpans: session.measureSpans,
                    progress: session.sessionProgress,
                    handMode: session.practiceHandMode,
                    currentPassage: session.activeRoundConfiguration?.passage,
                    currentMeasure: session.measureIndex?.occurrenceID(forStepIndex: session.currentStepIndex)?.sourceMeasureID
                )
            )
            .frame(width: 400, height: practiceViewHeight)
            .glassBackgroundEffect()
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                Button("返回选曲库", systemImage: "chevron.backward") {
                    onBackToLibrary()
                }
                // .buttonStyle(.bordered)

                if isAutoplayEnabled == false {
                    Button(manualAdvanceMode.nextButtonTitle, systemImage: "forward.fill") {
                        viewModel.skipStep()
                    }
                    // .buttonStyle(.bordered)
                    .disabled(viewModel.isAIPerformanceActive || viewModel.hasImportedSteps == false || viewModel
                        .practiceSessionViewModel.state == .completed)

                    Button(manualAdvanceMode.replayButtonTitle, systemImage: "speaker.wave.2.fill") {
                        if manualAdvanceMode == .measure {
                            viewModel.replayCurrentPracticeUnit()
                        } else {
                            viewModel.playCurrentPracticeStepSound()
                        }
                    }
                    // .buttonStyle(.bordered)
                    .disabled(
                        viewModel.isAIPerformanceActive ||
                            session.state == .ready ||
                            session.currentStep == nil
                    )
                }

                Toggle("自动播放", isOn: $isAutoplayEnabled)
                    .toggleStyle(.button)
                    // .buttonStyle(.bordered)
                .disabled(viewModel.isAIPerformanceActive)

                Button("设置", systemImage: "gearshape") {
                    isSettingsPresented.toggle()
                }
                // .buttonStyle(.bordered)

                Text("进度 \(viewModel.practiceProgressText)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                if isVirtualPianoMode, let status = viewModel.gazePlaneDiskStatusText {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
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
        .onChange(of: isAutoplayEnabled) {
            viewModel.setPracticeAutoplayEnabled(isAutoplayEnabled)
        }
        .onChange(of: session.latestFeedbackEvent) {
            viewModel.practiceFeedbackViewModel.present(session.latestFeedbackEvent)
        }
        .onChange(of: session.audioErrorMessage) {
            isAudioErrorAlertPresented = session.audioErrorMessage != nil
        }
        .alert("音频不可用", isPresented: $isAudioErrorAlertPresented) {
            Button("知道了") {
                session.clearAudioError()
            }
        } message: {
            Text(session.audioErrorMessage ?? "")
        }
        .onChange(of: session.autoplayErrorMessage) {
            isAutoplayErrorAlertPresented = session.autoplayErrorMessage != nil
        }
        .alert("无法自动播放", isPresented: $isAutoplayErrorAlertPresented) {
            Button("知道了") {
                session.clearAutoplayError()
            }
        } message: {
            Text(session.autoplayErrorMessage ?? "")
        }
        .onChange(of: viewModel.practiceSessionReplacementErrorMessage) {
            isSessionReplacementErrorAlertPresented = viewModel.practiceSessionReplacementErrorMessage != nil
        }
        .alert("无法应用设置", isPresented: $isSessionReplacementErrorAlertPresented) {
            Button("知道了") {
                viewModel.clearPracticeSessionReplacementError()
            }
        } message: {
            Text(viewModel.practiceSessionReplacementErrorMessage ?? "")
        }
        .onDisappear {
            viewModel.practiceFeedbackViewModel.cancel()
            isStepVisible = false
            hasRequestedImmersiveOpen = false
        }
        .sheet(isPresented: $isTakeLibraryPresented) {
            NavigationStack {
                TakeLibraryView(
                    takes: viewModel.takeLibraryTakes,
                    playbackViewModel: viewModel.takePlaybackViewModel,
                    isRecording: viewModel.isRecording,
                    errorMessage: viewModel.takeLibraryErrorMessage,
                    onErrorDismiss: { viewModel.dismissTakeLibraryError() },
                    onRename: { id, name in viewModel.renameTake(id: id, name: name) },
                    onDelete: { id in viewModel.deleteTake(id: id) },
                    onClearAll: { viewModel.clearAllTakes() },
                    makeMIDIExport: { take in try viewModel.makeMIDIExport(for: take) }
                )
                .navigationTitle("录制库")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            isTakeLibraryPresented = false
                        }
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 500)
        }
    }

    private var isVirtualPianoMode: Bool {
        viewModel.isVirtualPianoMode
    }

    private var virtualPerformerEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.aiPerformanceViewModel.isVirtualPerformerEnabled },
            set: { viewModel.setPracticeVirtualPerformerEnabled($0) }
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
                hand: token.hand,
                phase: token.phase,
                keyKind: PianoKeyboard88View.keyKind(for: midiNote)
            )
            return (midiNote, PianoKeyboard88Highlight(fill: .guide(style)))
        })
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
        onBackToLibrary: {}
    )
}
