import SwiftUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
    @Bindable var viewModel: SongLibraryViewModel
    let onBackToPreparation: @MainActor () -> Void
    let onStartPractice: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedEntryID: UUID?
    @State private var isAudioImporterPresented = false
    @State private var pendingAudioBindingEntryID: UUID?
    @State private var pendingDeletionEntryID: UUID?

    private var audioImporterTypes: [UTType] {
        let types = SongLibraryViewModel.supportedAudioFileExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        return types.isEmpty ? [.audio] : types
    }

    var body: some View {
        let entries = viewModel.entries
        let selectedIndex = entries.firstIndex(where: { $0.id == selectedEntryID })
        let selectedEntry = selectedIndex.map { entries[$0] }
        let selectedPresentation = selectedIndex.map {
            SongLibraryTrackPresentation(entry: entries[$0], index: $0)
        }
        let selectedIsPlaying =
            selectedEntry.map { viewModel.isListeningPlaying(entryID: $0.id) } ?? false
        let selectedDuration = resolvedDuration(
            presentation: selectedPresentation, selectedEntry: selectedEntry)
        let selectedCurrentTime = resolvedCurrentTime(selectedEntry: selectedEntry)
        let selectedProgress = selectedDuration > 0 ? selectedCurrentTime / selectedDuration : 0
        let requiresAudioImport =
            selectedEntry != nil && selectedEntry?.audioFileName == nil && selectedEntry?.isBundled != true
        let canPerformPlaybackAction = selectedEntry?.audioFileName != nil || requiresAudioImport

        VStack(spacing: 0) {
            LibraryTopBarView(onBack: onBackToPreparation)

            if entries.isEmpty {
                SongLibraryEmptyView(onImport: viewModel.didTapImportMusicXML)
            } else if let selectedEntry, let selectedPresentation {
                LibraryCrateView(
                    entries: entries,
                    selectedEntryID: $selectedEntryID,
                    playingEntryID: viewModel.currentListeningEntryID,
                    isPlaying: selectedIsPlaying,
                    reduceMotion: reduceMotion,
                    onSelectionChanged: didSelectEntry,
                    onTogglePlayback: togglePlayback,
                    onImportMusicXML: viewModel.didTapImportMusicXML,
                    onBindAudio: presentAudioImporter,
                    onDelete: requestDeletion
                )

                LibraryTrackInfoView(
                    presentation: selectedPresentation,
                    progress: selectedProgress,
                    currentTime: selectedCurrentTime,
                    duration: selectedDuration,
                    canSeek: viewModel.currentListeningEntryID == selectedEntry.id && selectedDuration > 0,
                    onSeek: { progress in
                        viewModel.seekListening(entryID: selectedEntry.id, progress: progress)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.bottom, 22)
            }
        }
        .frame(
            minWidth: 780,
            idealWidth: 1140,
            maxWidth: 1240,
            minHeight: LibraryDesignTokens.windowMinimumHeight,
            idealHeight: LibraryDesignTokens.windowIdealHeight,
            maxHeight: LibraryDesignTokens.windowMaximumHeight
        )
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                Button(
                    playbackButtonTitle(
                        requiresAudioImport: requiresAudioImport,
                        isPlaying: selectedIsPlaying
                    ),
                    systemImage: playbackButtonSystemImage(
                        requiresAudioImport: requiresAudioImport,
                        isPlaying: selectedIsPlaying
                    ),
                    action: toggleSelectedPlayback
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(canPerformPlaybackAction == false)

                Button("开始练习", systemImage: "music.note", action: startSelectedPractice)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(LibraryDesignTokens.accent)
                    .disabled(selectedEntry == nil)
            }
        }
        .fileImporter(
            isPresented: $isAudioImporterPresented,
            allowedContentTypes: audioImporterTypes,
            allowsMultipleSelection: false,
            onCompletion: handleAudioImport
        )
        .onAppear {
            viewModel.reload()
            synchronizeSelection()
        }
        .onChange(of: viewModel.entries) {
            synchronizeSelection()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.dismissError()
                    }
                }
            )
        ) {
            Button("好", action: viewModel.dismissError)
        } message: {
            Text(viewModel.errorMessage ?? "未知错误")
        }
        .confirmationDialog(
            "确认删除该曲目？",
            isPresented: Binding(
                get: { pendingDeletionEntryID != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingDeletionEntryID = nil
                    }
                }
            )
        ) {
            Button("删除", role: .destructive, action: deletePendingEntry)
            Button("取消", role: .cancel) {
                pendingDeletionEntryID = nil
            }
        } message: {
            Text("删除后将移除曲谱文件及已绑定音频文件，且无法撤销。")
        }
    }

    private func resolvedDuration(
        presentation: SongLibraryTrackPresentation?,
        selectedEntry: SongLibraryEntry?
    ) -> TimeInterval {
        if let selectedEntry,
            viewModel.currentListeningEntryID == selectedEntry.id,
            viewModel.listeningDuration > 0
        {
            return viewModel.listeningDuration
        }
        return presentation?.knownDuration ?? 0
    }

    private func resolvedCurrentTime(selectedEntry: SongLibraryEntry?) -> TimeInterval {
        guard let selectedEntry, viewModel.currentListeningEntryID == selectedEntry.id else { return 0 }
        return viewModel.listeningCurrentTime
    }

    private func playbackButtonTitle(requiresAudioImport: Bool, isPlaying: Bool) -> String {
        if requiresAudioImport {
            return "导入音频"
        }
        return isPlaying ? "暂停" : "播放"
    }

    private func playbackButtonSystemImage(requiresAudioImport: Bool, isPlaying: Bool) -> String {
        if requiresAudioImport {
            return "waveform.badge.plus"
        }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    private func synchronizeSelection() {
        let entries = viewModel.entries
        guard entries.isEmpty == false else {
            selectedEntryID = nil
            return
        }

        if let selectedEntryID, entries.contains(where: { $0.id == selectedEntryID }) {
            return
        }

        selectedEntryID =
            viewModel.index.lastSelectedEntryID.flatMap { preferredID in
                entries.first(where: { $0.id == preferredID })?.id
            } ?? entries.first?.id
    }

    private func didSelectEntry(_ entryID: UUID) {
        if let currentListeningEntryID = viewModel.currentListeningEntryID,
            currentListeningEntryID != entryID
        {
            viewModel.stopListening()
        }
    }

    private func toggleSelectedPlayback() {
        guard let selectedEntryID else { return }
        togglePlayback(selectedEntryID)
    }

    private func togglePlayback(_ entryID: UUID) {
        guard let entry = viewModel.entries.first(where: { $0.id == entryID }) else { return }
        guard entry.audioFileName != nil else {
            if entry.isBundled == true {
                viewModel.errorMessage = "此内置曲目没有可播放的音频。"
            } else {
                presentAudioImporter(entryID)
            }
            return
        }
        viewModel.didTapListen(entryID: entryID)
    }

    private func startSelectedPractice() {
        guard let selectedEntryID, viewModel.preparePractice(entryID: selectedEntryID) else { return }
        onStartPractice()
    }

    private func presentAudioImporter(_ entryID: UUID) {
        guard let entry = viewModel.entries.first(where: { $0.id == entryID }), entry.isBundled != true else {
            return
        }
        pendingAudioBindingEntryID = entryID
        isAudioImporterPresented = true
    }

    private func requestDeletion(_ entryID: UUID) {
        guard let entry = viewModel.entries.first(where: { $0.id == entryID }), entry.isBundled != true else {
            return
        }
        pendingDeletionEntryID = entryID
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        defer { pendingAudioBindingEntryID = nil }

        do {
            let urls = try result.get()
            guard let entryID = pendingAudioBindingEntryID, let audioURL = urls.first else { return }
            viewModel.bindAudio(entryID: entryID, from: audioURL)
        } catch {
            viewModel.errorMessage = "导入音频失败：\(error.localizedDescription)"
        }
    }

    private func deletePendingEntry() {
        guard let entryID = pendingDeletionEntryID else { return }
        viewModel.deleteEntry(entryID: entryID)
        pendingDeletionEntryID = nil
        synchronizeSelection()
    }
}

#Preview {
    let worldAnchorCalibrationStore = WorldAnchorCalibrationStore()
    let keyGeometryService = PianoKeyGeometryService()
    let parser: MusicXMLParserProtocol = MusicXMLParser()
    let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
    let arTrackingService = ARTrackingService()
    let calibrationCaptureService = CalibrationPointCaptureService()
    let calibrationRepository = CalibrationRepository(
        worldAnchorCalibrationStore: worldAnchorCalibrationStore)
    let practicePreparationService: PracticePreparationServiceProtocol =
        PracticePreparationService(parser: parser, stepBuilder: stepBuilder)
    let songLibraryIndexStore: SongLibraryIndexStoreProtocol = SongLibraryIndexStore()
    let songFileStore: SongFileStoreProtocol = SongFileStore()
    let audioImportService: AudioImportServiceProtocol = AudioImportService()
    let songLibraryPaths = SongLibraryPaths()
    let bundledSongLibraryProvider: BundledSongLibraryProviderProtocol = BundledSongLibraryProvider()
    let songAudioPlayer: SongAudioPlayerProtocol = SongAudioPlayer()
    let practiceSetupState = PracticeSetupState()
    let appState = AppState(
        arTrackingService: arTrackingService,
        calibrationCaptureService: calibrationCaptureService,
        calibrationRepository: calibrationRepository,
        keyGeometryService: keyGeometryService
    )
    let viewModel = SongLibraryViewModel(
        appState: appState,
        practiceSetupState: practiceSetupState,
        practicePreparationService: practicePreparationService,
        indexStore: songLibraryIndexStore,
        fileStore: songFileStore,
        audioImportService: audioImportService,
        paths: songLibraryPaths,
        bundledProvider: bundledSongLibraryProvider,
        audioPlayer: songAudioPlayer
    )
    return SongLibraryView(
        viewModel: viewModel,
        onBackToPreparation: {},
        onStartPractice: {}
    )
}
