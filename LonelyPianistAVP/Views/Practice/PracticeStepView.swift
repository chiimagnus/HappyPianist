import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel
    let onBackToLibrary: () -> Void
    let onRestartFromTypePicker: () -> Void
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var isLocalizationPopoverPresented = false
    @State private var isSettingsPopoverPresented = false
    @State private var isAudioErrorAlertPresented = false
    @State private var isAutoplayErrorAlertPresented = false
    @State private var isTakeLibraryPresented = false

    @State private var isVirtualPerformerEnabled = false
    @State private var isAutoplayEnabled = false
    @AppStorage("practiceManualAdvanceMode") private var manualAdvanceModeRawValue = ManualAdvanceMode.step.rawValue
    @AppStorage("practiceAudioRecognitionDebugOverlayEnabled") private var isAudioDebugOverlayEnabled = false

    var body: some View {
        practiceSurface
            .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 18)
            .overlay {
                ZStack(alignment: .topTrailing) {
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
                    Button("回到选曲库", systemImage: "chevron.backward") {
                        onBackToLibrary()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()

                    Button("重新选择钢琴类型", systemImage: "arrow.uturn.backward") {
                        onRestartFromTypePicker()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()

                    if isAutoplayEnabled == false {
                        Button(manualAdvanceMode.nextButtonTitle, systemImage: "forward.fill") {
                            viewModel.skipStep()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(viewModel.isAIPerformanceActive || viewModel.hasImportedSteps == false || viewModel
                            .practiceSessionViewModel
                            .state == .completed)

                        Button(manualAdvanceMode.replayButtonTitle, systemImage: "speaker.wave.2.fill") {
                            if manualAdvanceMode == .measure {
                                viewModel.replayCurrentPracticeUnit()
                            } else {
                                viewModel.playCurrentPracticeStepSound()
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(
                            viewModel.isAIPerformanceActive ||
                                viewModel.practiceSessionViewModel.state == .ready ||
                                viewModel.practiceSessionViewModel.currentStep == nil
                        )
                    }

                    Toggle("自动播放", isOn: $isAutoplayEnabled)
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(viewModel.isAIPerformanceActive)

                    Button("设置", systemImage: "gearshape") {
                        isSettingsPopoverPresented.toggle()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    .hoverEffect()
                    .disabled(viewModel.isAIPerformanceActive)
                    .popover(isPresented: $isSettingsPopoverPresented) {
                        PracticeStepSettingsPopover(
                            virtualPerformerEnabled: $isVirtualPerformerEnabled,
                            backendStatusText: viewModel.backendStatusText,
                            lastImprovStatusText: viewModel.lastImprovStatusText,
                            recordingSourceText: viewModel.recordingSourceText,
                            isAIPerformanceActive: viewModel.isAIPerformanceActive,
                            isVirtualPianoMode: isVirtualPianoMode,
                            gazePlaneDiskStatusText: viewModel.gazePlaneDiskStatusText,
                            onOpenTakeLibrary: {
                                isSettingsPopoverPresented = false
                                isTakeLibraryPresented = true
                            },
                            onRetryVirtualPianoPlacement: {
                                viewModel.retryVirtualPianoPlacement()
                            },
                            onDebugTriggerAIPerformance: {
                                #if DEBUG && targetEnvironment(simulator)
                                Task { @MainActor in
                                    await viewModel.debugTriggerAIPerformance()
                                }
                                #endif
                            }
                        )
                    }

                    if viewModel.isRecording {
                        Button("结束录制", systemImage: "stop.circle.fill") {
                            viewModel.stopRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()

                        Text(viewModel.recordingElapsedText)
                            .monospacedDigit()
                            .foregroundStyle(.red)
                    } else {
                        Button("开始录制", systemImage: "circle.fill") {
                            viewModel.startRecording()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(viewModel.canRecord == false || viewModel.isAIPerformanceActive || viewModel.takePlaybackController.isPlaying)
                    }

                    if isAutoplayEnabled {
                        Text(viewModel.practiceSessionViewModel.isSustainPedalDown ? "Pedal ↓" : "Pedal ↑")
                            .foregroundStyle(.secondary)
                    }

                    Text("进度 \(viewModel.practiceProgressText)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if isVirtualPianoMode, let status = viewModel.gazePlaneDiskStatusText {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isAutoplayEnabled == false, isVirtualPianoMode == false {
                        Button("定位", systemImage: "scope") {
                            isLocalizationPopoverPresented.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle)
                        .hoverEffect()
                        .disabled(viewModel.isAIPerformanceActive)
                        .popover(isPresented: $isLocalizationPopoverPresented) {
                            PracticeStepLocalizationPopover(
                                practiceLocalizationStatusText: viewModel.practiceLocalizationStatusText,
                                step3ARStatusText: viewModel.step3ARStatusText,
                                step3HandAssistStatusText: viewModel.step3HandAssistStatusText,
                                step3AudioStatusText: viewModel.step3AudioStatusText,
                                canRetryPracticeLocalization: viewModel.canRetryPracticeLocalization,
                                shouldSuggestCalibrationStep: viewModel.shouldSuggestCalibrationStep,
                                isAIPerformanceActive: viewModel.isAIPerformanceActive,
                                onRetryLocalization: {
                                    Task { @MainActor in
                                        await viewModel.retryPracticeLocalization(
                                            using: openImmersiveSpace,
                                            dismissImmersiveSpace: dismissImmersiveSpace
                                        )
                                    }
                                },
                                onRestartFromTypePicker: {
                                    onRestartFromTypePicker()
                                }
                            )
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
                    viewModel.setPracticeVirtualPianoEnabled(isVirtualPianoMode)
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
            .onChange(of: isVirtualPerformerEnabled) {
                viewModel.setPracticeVirtualPerformerEnabled(isVirtualPerformerEnabled)
            }
            .onChange(of: isAutoplayEnabled) {
                viewModel.setPracticeAutoplayEnabled(isAutoplayEnabled)
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
            .onChange(of: viewModel.practiceSessionViewModel.autoplayErrorMessage) {
                isAutoplayErrorAlertPresented = viewModel.practiceSessionViewModel.autoplayErrorMessage != nil
            }
            .alert("无法自动播放", isPresented: $isAutoplayErrorAlertPresented) {
                Button("知道了") {
                    viewModel.practiceSessionViewModel.clearAutoplayError()
                }
            } message: {
                Text(viewModel.practiceSessionViewModel.autoplayErrorMessage ?? "")
            }
            .onDisappear {
                isStepVisible = false
                hasRequestedImmersiveOpen = false
                isVirtualPerformerEnabled = false
                viewModel.stopRecording()
                viewModel.takePlaybackController.stop()
                viewModel.setPracticeAutoplayEnabled(false)
                viewModel.setPracticeVirtualPianoEnabled(false)
                viewModel.setPracticeVirtualPerformerEnabled(false)
                viewModel.resetPracticeLocalizationState()
                Task { @MainActor in
                    await viewModel.closeImmersiveForStep(using: dismissImmersiveSpace)
                    await viewModel.recoverImmersiveStateIfStuck()
                }
            }
            .sheet(isPresented: $isTakeLibraryPresented) {
                NavigationStack {
                    TakeLibraryView(
                        takes: viewModel.takeLibraryTakes,
                        playbackController: viewModel.takePlaybackController,
                        isRecording: viewModel.isRecording,
                        errorMessage: viewModel.takeLibraryErrorMessage,
                        onErrorDismiss: { viewModel.dismissTakeLibraryError() },
                        onRename: { id, name in viewModel.renameTake(id: id, name: name) },
                        onDelete: { id in viewModel.deleteTake(id: id) },
                        onClearAll: { viewModel.clearAllTakes() }
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

    private var practiceSurface: some View {
        VStack(spacing: 21) {
            GrandStaffNotationView(
                guides: viewModel.practiceSessionViewModel.highlightGuides,
                currentGuide: viewModel.practiceSessionViewModel.currentPianoHighlightGuide,
                measureSpans: viewModel.practiceSessionViewModel.notationMeasureSpans,
                context: viewModel.practiceSessionViewModel.currentGrandStaffNotationContext,
                scrollTickProvider: viewModel.practiceSessionViewModel.autoplayState == .playing ? {
                    viewModel.practiceSessionViewModel.smoothNotationScrollTick()
                } : nil
            )
            .frame(height: 260)

            PianoKeyboard88View(
                highlightedMIDINotes: highlightedMIDINotes,
                highlightOccurrenceID: viewModel.practiceSessionViewModel.currentPianoHighlightGuide?.id,
                triggeredMIDINotes: triggeredMIDINotes,
                fingeringByMIDINote: fingeringByMIDINote,
                highlightColorByMIDINote: highlightColorByMIDINote
            )
            .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
        }
    }

    private var manualAdvanceMode: ManualAdvanceMode {
        ManualAdvanceMode.storageValue(from: manualAdvanceModeRawValue)
    }

    private var isVirtualPianoMode: Bool {
        viewModel.isVirtualPianoMode
    }

    private var highlightedMIDINotes: Set<Int> {
        viewModel.practiceSessionViewModel.currentPianoHighlightGuide?.highlightedMIDINotes ?? []
    }

    private var fingeringByMIDINote: [Int: String] {
        guard isAutoplayEnabled else { return [:] }
        return viewModel.practiceSessionViewModel.currentPianoHighlightGuide?.fingeringByMIDINote ?? [:]
    }

    private var triggeredMIDINotes: Set<Int> {
        guard isAutoplayEnabled else { return [] }
        let notes = viewModel.practiceSessionViewModel.currentPianoHighlightGuide?.triggeredNotes ?? []
        return Set(notes.map(\.midiNote))
    }

    private var highlightColorByMIDINote: [Int: Color] {
        guard let guide = viewModel.practiceSessionViewModel.currentPianoHighlightGuide else { return [:] }

        func resolvedHand(notes: [PianoHighlightNote]) -> ScoreHand? {
            guard notes.isEmpty == false else { return nil }
            if notes.contains(where: { $0.hand == .left }) { return .left }
            return .right
        }

        var triggeredNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in guide.triggeredNotes {
            triggeredNotesByMidi[note.midiNote, default: []].append(note)
        }

        var activeNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in guide.activeNotes {
            activeNotesByMidi[note.midiNote, default: []].append(note)
        }

        var result: [Int: Color] = [:]
        for midiNote in guide.highlightedMIDINotes {
            let preferred = triggeredNotesByMidi[midiNote].flatMap(resolvedHand)
                ?? activeNotesByMidi[midiNote].flatMap(resolvedHand)

            if preferred == .left {
                result[midiNote] = PracticeHandPalette.leftHandKeyColor
            }
        }
        return result
    }

}

#Preview("Step 3") {
    let services = AppServices()
    let flowState = FlowState()
    let appState = AppState(
        arTrackingService: services.arTrackingService,
        calibrationCaptureService: services.calibrationCaptureService,
        calibrationRepository: services.calibrationRepository,
        keyGeometryService: services.keyGeometryService
    )
    let viewModel = ARGuideViewModel(
        appState: appState,
        flowState: flowState,
        pianoModeRegistry: services.pianoModeRegistry,
        practiceSessionViewModelFactory: services.practiceSessionViewModelFactory
    )
    PracticeStepView(
        viewModel: viewModel,
        onBackToLibrary: {},
        onRestartFromTypePicker: {}
    )
}
