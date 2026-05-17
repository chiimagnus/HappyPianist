import SwiftUI

struct PracticeStepView: View {
    @Bindable var viewModel: ARGuideViewModel
    let onBackToLibrary: () -> Void
    let onRestartFromTypePicker: () -> Void
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var hasRequestedImmersiveOpen = false
    @State private var isStepVisible = false
    @State private var isSettingsPopoverPresented = false
    @State private var isAudioErrorAlertPresented = false
    @State private var isAutoplayErrorAlertPresented = false
    @State private var isTakeLibraryPresented = false

    @State private var isVirtualPerformerEnabled = false
    @State private var isAutoplayEnabled = false
    @AppStorage("practiceManualAdvanceMode") private var manualAdvanceModeRawValue = ManualAdvanceMode.step.rawValue

    var body: some View {
        let session = viewModel.practiceSessionViewModel
        let currentGuide = session.currentPianoHighlightGuide

        VStack(spacing: 21) {
            GrandStaffNotationView(
                guides: session.highlightGuides,
                currentGuide: currentGuide,
                measureSpans: session.notationMeasureSpans,
                context: session.currentGrandStaffNotationContext,
                scrollTickProvider: session.autoplayState == .playing ? {
                    session.smoothNotationScrollTick()
                } : nil
            )
            .frame(height: 260)

            PianoKeyboard88View(
                highlightedMIDINotes: highlightedMIDINotes,
                highlightOccurrenceID: currentGuide?.id,
                triggeredMIDINotes: triggeredMIDINotes,
                fingeringByMIDINote: fingeringByMIDINote,
                highlightColorByMIDINote: highlightColorByMIDINote
            )
            .aspectRatio(PianoKeyboard88View.aspectRatio, contentMode: .fit)
        }
        .containerRelativeFrame(.horizontal, count: 10, span: 9, spacing: 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                Button("回到选曲库", systemImage: "chevron.backward") {
                    onBackToLibrary()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                // .hoverEffect()

                if isAutoplayEnabled == false {
                    Button(manualAdvanceMode.nextButtonTitle, systemImage: "forward.fill") {
                        viewModel.skipStep()
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    // .hoverEffect()
                    .disabled(viewModel.isAIPerformanceActive || viewModel.hasImportedSteps == false || viewModel
                        .practiceSessionViewModel.state == .completed)

                    Button(manualAdvanceMode.replayButtonTitle, systemImage: "speaker.wave.2.fill") {
                        if manualAdvanceMode == .measure {
                            viewModel.replayCurrentPracticeUnit()
                        } else {
                            viewModel.playCurrentPracticeStepSound()
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    // .hoverEffect()
                    .disabled(
                        viewModel.isAIPerformanceActive ||
                            session.state == .ready ||
                            session.currentStep == nil
                    )
                }

                Toggle("自动播放", isOn: $isAutoplayEnabled)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle)
                    // .hoverEffect()
                    .disabled(viewModel.isAIPerformanceActive)

                Button("设置", systemImage: "gearshape") {
                    isSettingsPopoverPresented.toggle()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle)
                .hoverEffect()
                .disabled(viewModel.isAIPerformanceActive)
                .popover(isPresented: $isSettingsPopoverPresented) {
                    PracticeSettingsView(
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
                    .disabled(viewModel.canRecord == false || viewModel.isAIPerformanceActive || viewModel
                        .takePlaybackController.isPlaying)
                }

                if isAutoplayEnabled {
                    Text(session.isSustainPedalDown ? "Pedal ↓" : "Pedal ↑")
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
            }
        }
        .buttonBorderShape(.roundedRectangle)
        .onAppear {
            isStepVisible = true
            guard hasRequestedImmersiveOpen == false else { return }
            hasRequestedImmersiveOpen = true

            Task { @MainActor in
                session.refreshAudioRecognitionFromSettings()
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

    private var manualAdvanceMode: ManualAdvanceMode {
        ManualAdvanceMode.storageValue(from: manualAdvanceModeRawValue)
    }

    private var isVirtualPianoMode: Bool {
        viewModel.isVirtualPianoMode
    }

    private var highlightedMIDINotes: Set<Int> {
        let session = viewModel.practiceSessionViewModel
        return session.currentPianoHighlightGuide?.highlightedMIDINotes ?? []
    }

    private var fingeringByMIDINote: [Int: String] {
        guard isAutoplayEnabled else { return [:] }
        let session = viewModel.practiceSessionViewModel
        return session.currentPianoHighlightGuide?.fingeringByMIDINote ?? [:]
    }

    private var triggeredMIDINotes: Set<Int> {
        guard isAutoplayEnabled else { return [] }
        let session = viewModel.practiceSessionViewModel
        let notes = session.currentPianoHighlightGuide?.triggeredNotes ?? []
        return Set(notes.map(\.midiNote))
    }

    private var highlightColorByMIDINote: [Int: Color] {
        let session = viewModel.practiceSessionViewModel
        guard let guide = session.currentPianoHighlightGuide else { return [:] }

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

private enum PracticeHandPalette {
    static let leftHandKeyColor = Color.cyan
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
