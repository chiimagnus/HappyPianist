import Foundation
import Observation

@MainActor
@Observable
final class SongLibraryViewModel {
    private let arGuideViewModel: ARGuideViewModel
    private let indexStore: SongLibraryIndexStoreProtocol
    private let fileStore: SongFileStoreProtocol
    private let audioImportService: AudioImportServiceProtocol
    private let bundledProvider: BundledSongLibraryProviderProtocol
    private let bootstrapLoader: (any SongLibraryBootstrapLoading)?
    private var bundledEntries: [SongLibraryEntry]
    private let practicePreparationService: PracticePreparationServiceProtocol
    private let audioPlaybackController: SongAudioPlaybackStateController
    private let practiceProgressRepository: any PracticeProgressRepositoryProtocol
    private let diagnosticsReporter: any DiagnosticsReporting
    private let selectionSettleSleeper: any SleeperProtocol
    private let selectionSettleDelay: Duration
    @ObservationIgnored private var playbackProgressTask: Task<Void, Never>?
    @ObservationIgnored private var practicePreparationTask: Task<Void, Never>?
    @ObservationIgnored private var practicePreparationGeneration = 0
    private var recordedPreparationFailureID: UUID?

    static let supportedAudioFileExtensions = ["mp3", "m4a"]
    private static let supportedAudioFileExtensionSet = Set(supportedAudioFileExtensions)

    var index: SongLibraryIndex = .empty
    var errorMessage: String?
    private(set) var bootstrapFailureMessage: String?
    private(set) var isLibraryLoading = false
    private(set) var hasLoadedLibrary = false
    var currentListeningEntryID: UUID?
    var isCurrentListeningPlaying = false
    var listeningCurrentTime: TimeInterval = 0
    var listeningDuration: TimeInterval = 0
    var isMusicXMLImporterPresented = false
    var practicePreparationState: LibraryPracticePreparationState = .idle
    var selectedPracticeEntryID: UUID?
    var practiceProgressBySongID: [UUID: SongPracticeProgress] = [:]

    var isPreparingPractice: Bool {
        if case .loading = practicePreparationState {
            return true
        }
        return false
    }

    var isSelectedPracticeReady: Bool {
        guard case let .ready(entryID, _) = practicePreparationState else { return false }
        return entryID == selectedPracticeEntryID
    }

    var wasSelectedPreparationFailureRecorded: Bool {
        guard case let .failure(failure) = practicePreparationState else { return false }
        return recordedPreparationFailureID == failure.id
    }

    init(
        arGuideViewModel: ARGuideViewModel,
        practicePreparationService: PracticePreparationServiceProtocol,
        indexStore: SongLibraryIndexStoreProtocol,
        fileStore: SongFileStoreProtocol,
        audioImportService: AudioImportServiceProtocol,
        bundledProvider: BundledSongLibraryProviderProtocol,
        audioPlayer: SongAudioPlayerProtocol,
        practiceProgressRepository: any PracticeProgressRepositoryProtocol,
        diagnosticsReporter: any DiagnosticsReporting,
        bootstrapLoader: (any SongLibraryBootstrapLoading)? = nil,
        initialSnapshot: SongLibraryBootstrapSnapshot? = nil,
        selectionSettleSleeper: any SleeperProtocol = TaskSleeper(),
        selectionSettleDelay: Duration = .milliseconds(200)
    ) {
        self.arGuideViewModel = arGuideViewModel
        self.practicePreparationService = practicePreparationService
        self.indexStore = indexStore
        self.fileStore = fileStore
        self.audioImportService = audioImportService
        self.bundledProvider = bundledProvider
        self.bootstrapLoader = bootstrapLoader
        self.practiceProgressRepository = practiceProgressRepository
        self.diagnosticsReporter = diagnosticsReporter
        self.selectionSettleSleeper = selectionSettleSleeper
        self.selectionSettleDelay = selectionSettleDelay
        switch initialSnapshot {
        case let .loaded(initialIndex, initialBundledEntries):
            index = initialIndex
            bundledEntries = initialBundledEntries
            hasLoadedLibrary = true
        case let .blocked(failure):
            bundledEntries = []
            bootstrapFailureMessage = failure.message
        case nil:
            bundledEntries = []
        }
        audioPlaybackController = SongAudioPlaybackStateController(player: audioPlayer)

        audioPlaybackController.onStateChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncListeningState()
            }
        }
    }

    var entries: [SongLibraryEntry] {
        var seenEntryIDs: Set<UUID> = []
        return (bundledEntries + index.entries).filter { entry in
            seenEntryIDs.insert(entry.id).inserted
        }
    }

    func loadLibraryIfNeeded() async {
        guard hasLoadedLibrary == false, isLibraryLoading == false else { return }
        guard let bootstrapLoader else {
            hasLoadedLibrary = true
            return
        }

        isLibraryLoading = true
        let snapshot = await bootstrapLoader.load()
        switch snapshot {
        case let .loaded(loadedIndex, loadedBundledEntries):
            index = loadedIndex
            bundledEntries = loadedBundledEntries
            bootstrapFailureMessage = nil
            hasLoadedLibrary = true
        case let .blocked(failure):
            bootstrapFailureMessage = failure.message
        }
        isLibraryLoading = false
    }

    func reload() async {
        do {
            index = try await indexStore.load()
        } catch {
            errorMessage = "加载乐曲库失败：\(error.localizedDescription)"
        }
    }

    func reloadPracticeProgress() async {
        guard case let .loaded(document) = await practiceProgressRepository.load() else {
            practiceProgressBySongID = [:]
            return
        }
        practiceProgressBySongID = Dictionary(
            document.songs.map { ($0.identity.songID, $0) },
            uniquingKeysWith: { current, candidate in
                current.updatedAt >= candidate.updatedAt ? current : candidate
            }
        )
    }

    var preparedRoundConfigurationController: PracticeRoundConfigurationController? {
        currentPreparedPracticeSession?.roundConfigurationController
    }

    var preparedMeasureSpans: [MusicXMLMeasureSpan] {
        currentPreparedPracticeSession?.measureSpans ?? []
    }

    var selectedPracticePresentation: LibraryPracticePanelPresentation? {
        guard case let .ready(entryID, identity) = practicePreparationState,
              entryID == selectedPracticeEntryID,
              let session = currentPreparedPracticeSession,
              let configuration = session.roundConfigurationController.pendingConfiguration
        else { return nil }

        let sessionProgress = session.sessionProgress?.identity == identity
            ? session.sessionProgress
            : nil
        let storedProgress = practiceProgressBySongID[entryID]?.identity == identity
            ? practiceProgressBySongID[entryID]
            : nil
        let currentMeasure = session.measureIndex?
            .occurrenceID(forStepIndex: session.currentStepIndex)?
            .sourceMeasureID

        return LibraryPracticePanelPresentation(
            identity: identity,
            measureSpans: session.measureSpans,
            progress: sessionProgress ?? storedProgress,
            configuration: configuration,
            currentMeasure: currentMeasure
        )
    }

    private var currentPreparedPracticeSession: PracticeSessionViewModel? {
        let session = arGuideViewModel.practiceSessionViewModel
        guard case let .ready(entryID, identity) = practicePreparationState,
              entryID == selectedPracticeEntryID,
              session.songIdentity == identity
        else { return nil }
        return session
    }

    var canStartSelectedPractice: Bool {
        isSelectedPracticeReady && preparedRoundConfigurationController?.pendingConfiguration != nil
    }

    @discardableResult
    func startSelectedPractice() -> Bool {
        guard canStartSelectedPractice,
              let session = currentPreparedPracticeSession
        else { return false }
        if session.roundConfigurationController.hasPendingChanges {
            _ = session.applyPendingRoundConfiguration()
        }
        return session.activeRange != nil && session.activeRangeDiagnostic == nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func didTapImportMusicXML() {
        isMusicXMLImporterPresented = true
    }

    func importMusicXML(from selectedURLs: [URL]) async {
        guard selectedURLs.isEmpty == false else { return }

        do {
            for url in selectedURLs {
                let imported = try fileStore.importMusicXML(from: url)
                let entry = SongLibraryEntry(
                    id: UUID(),
                    displayName: URL(fileURLWithPath: imported.sourceFileName)
                        .deletingPathExtension()
                        .lastPathComponent,
                    musicXMLFileName: imported.storedFileName,
                    importedAt: imported.importedAt,
                    audioFileName: nil
                )

                do {
                    index = try await indexStore.appendUserEntry(entry)
                } catch {
                    try? fileStore.deleteScoreFile(named: imported.storedFileName)
                    throw error
                }
            }
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func selectEntryForPractice(_ entryID: UUID) {
        guard entries.contains(where: { $0.id == entryID }) else {
            cancelPracticePreparation()
            return
        }
        if selectedPracticeEntryID == entryID {
            switch practicePreparationState {
            case .loading, .ready:
                return
            case .idle, .failure:
                break
            }
        }
        beginPracticePreparation(entryID: entryID)
    }

    func retrySelectedPracticePreparation() {
        guard let selectedPracticeEntryID else { return }
        beginPracticePreparation(entryID: selectedPracticeEntryID)
    }

    func cancelPracticePreparation() {
        practicePreparationTask?.cancel()
        practicePreparationTask = nil
        practicePreparationGeneration += 1
        selectedPracticeEntryID = nil
        recordedPreparationFailureID = nil
        practicePreparationState = .idle
    }

    private func beginPracticePreparation(entryID: UUID) {
        practicePreparationTask?.cancel()
        practicePreparationGeneration += 1
        let generation = practicePreparationGeneration
        selectedPracticeEntryID = entryID
        recordedPreparationFailureID = nil
        practicePreparationState = .loading(entryID: entryID)
        practicePreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await selectionSettleSleeper.sleep(for: selectionSettleDelay)
                try Task.checkCancellation()
            } catch {
                return
            }
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else {
                return
            }
            await persistSelectedEntry(entryID, generation: generation)
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else {
                return
            }
            await prepareSelectedEntry(entryID: entryID, generation: generation)
        }
    }

    private func prepareSelectedEntry(entryID: UUID, generation: Int) async {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        let fileReference = diagnosticFileReference(for: entry)

        do {
            let scoreURL: URL
            if entry.isBundled == true {
                guard let bundledURL = bundledProvider.musicXMLURL(fileName: entry.musicXMLFileName) else {
                    throw PracticePreparationError.scoreFileNotFound
                }
                scoreURL = bundledURL
            } else {
                do {
                    scoreURL = try fileStore.scoreFileURL(fileName: entry.musicXMLFileName)
                } catch {
                    let cocoaError = error as? CocoaError
                    if cocoaError?.code == .fileNoSuchFile || cocoaError?.code == .fileReadNoSuchFile {
                        throw PracticePreparationError.scoreFileNotFound
                    }
                    throw PracticePreparationError.scoreFileUnreadable(
                        reason: PracticePreparationErrorDetails.safeErrorSummary(error)
                    )
                }
            }

            let file = ImportedMusicXMLFile(
                fileName: entry.displayName,
                storedURL: scoreURL,
                importedAt: entry.importedAt
            )
            let prepared = try await practicePreparationService.prepare(
                songID: entry.id,
                from: scoreURL,
                file: file
            )
            try Task.checkCancellation()
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else { return }
            guard prepared.steps.isEmpty == false else {
                throw PracticePreparationError.noPlayableNotes
            }
            guard prepared.measureSpans.isEmpty == false else {
                throw PracticePreparationError.missingMeasureStructure
            }

            guard await arGuideViewModel.applyPreparedPractice(
                prepared,
                isCurrent: { [weak self] in
                    self?.isCurrentPracticePreparation(
                        entryID: entryID,
                        generation: generation
                    ) == true
                }
            ) else { return }
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else { return }
            practicePreparationState = .ready(entryID: entryID, identity: prepared.identity)
            practicePreparationTask = nil
            _ = await diagnosticsReporter.record(
                DiagnosticEvent(
                    severity: .info,
                    code: .practicePreparationSucceeded,
                    category: .practicePreparation,
                    stage: "selectedScorePreparation",
                    summary: "曲谱练习数据已准备完成",
                    reason: "Prepared \(prepared.steps.count) steps and \(prepared.measureSpans.count) measure occurrences.",
                    songID: entryID,
                    scoreRevision: prepared.identity.scoreRevision,
                    file: fileReference,
                    persistence: .exportable
                )
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else { return }
            let preparationError = (error as? PracticePreparationError) ?? .unexpected(
                stage: "selectedScorePreparation",
                reason: PracticePreparationErrorDetails.safeErrorSummary(error)
            )
            let failure = LibraryPracticePreparationFailure.map(
                preparationError,
                entryID: entryID,
                file: fileReference
            )
            practicePreparationState = .failure(failure)
            practicePreparationTask = nil
            let recordResult = await diagnosticsReporter.record(failure.diagnosticEvent)
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation),
                  case let .failure(currentFailure) = practicePreparationState,
                  currentFailure.id == failure.id
            else { return }
            recordedPreparationFailureID = recordResult.persistedForExport ? failure.id : nil
        }
    }

    private func isCurrentPracticePreparation(entryID: UUID, generation: Int) -> Bool {
        generation == practicePreparationGeneration &&
            selectedPracticeEntryID == entryID &&
            Task.isCancelled == false
    }

    private func diagnosticFileReference(for entry: SongLibraryEntry) -> DiagnosticFileReference? {
        let fileName = URL(fileURLWithPath: entry.musicXMLFileName).lastPathComponent
        let relativePath = entry.isBundled == true
            ? "Bundle/\(fileName)"
            : "SongLibrary/scores/\(fileName)"
        return DiagnosticFileReference(fileName: fileName, relativePath: relativePath)
    }

    private func persistSelectedEntry(_ entryID: UUID, generation: Int) async {
        guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else { return }
        do {
            let updatedIndex = try await indexStore.setLastSelectedEntryID(entryID)
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else { return }
            index = updatedIndex
        } catch {
            guard isCurrentPracticePreparation(entryID: entryID, generation: generation) else { return }
            errorMessage = "保存曲库选择失败：\(error.localizedDescription)"
        }
    }

    func deleteEntry(entryID: UUID) async {
        if bundledEntries.contains(where: { $0.id == entryID }) {
            errorMessage = "内置曲目无法删除。"
            return
        }
        guard index.entries.contains(where: { $0.id == entryID }) else {
            return
        }
        if currentListeningEntryID == entryID {
            stopListening()
        }

        do {
            let fallbackID = entries.last(where: { $0.id != entryID })?.id
            let mutation = try await indexStore.removeUserEntry(
                id: entryID,
                fallbackLastSelectedEntryID: fallbackID
            )
            guard case let .applied(updatedIndex, entry) = mutation else {
                index = mutation.index
                return
            }
            index = updatedIndex

            do {
                try await practiceProgressRepository.remove(songID: entry.id)
            } catch {
                errorMessage = "曲目已删除，但练习进度清理失败：\(error.localizedDescription)"
            }

            do {
                try fileStore.deleteScoreFile(named: entry.musicXMLFileName)
                if let audioFileName = entry.audioFileName {
                    try fileStore.deleteAudioFile(named: audioFileName)
                }
            } catch {
                errorMessage = "曲目已从索引移除，但文件删除失败：\(error.localizedDescription)"
            }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func bindAudio(entryID: UUID, from sourceURL: URL) async {
        if bundledEntries.contains(where: { $0.id == entryID }) {
            errorMessage = "内置曲目不支持绑定外部音频文件。"
            return
        }
        guard let entry = index.entries.first(where: { $0.id == entryID }) else {
            return
        }

        let fileExtension = sourceURL.pathExtension.lowercased()
        guard Self.supportedAudioFileExtensionSet.contains(fileExtension) else {
            errorMessage = "仅支持导入 mp3 或 m4a 音频文件。"
            return
        }

        do {
            let importedAudioFileName = try audioImportService.importAudio(from: sourceURL)

            let previousAudioFileName = entry.audioFileName

            do {
                let mutation = try await indexStore.updateAudioFileName(
                    entryID: entryID,
                    expectedCurrentFileName: previousAudioFileName,
                    newFileName: importedAudioFileName
                )
                guard case let .applied(updatedIndex, _) = mutation else {
                    index = mutation.index
                    try? fileStore.deleteAudioFile(named: importedAudioFileName)
                    errorMessage = "曲目已发生变化，请重试导入音频。"
                    return
                }
                if currentListeningEntryID == entryID {
                    stopListening()
                }
                index = updatedIndex
                if let previousAudioFileName {
                    try? fileStore.deleteAudioFile(named: previousAudioFileName)
                }
            } catch {
                try? fileStore.deleteAudioFile(named: importedAudioFileName)
                throw error
            }
        } catch {
            errorMessage = "导入音频失败：\(error.localizedDescription)"
        }
    }

    func didTapListen(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return
        }
        guard let audioFileName = entry.audioFileName else {
            errorMessage = "此曲目未绑定音频文件，可再次导入音频。"
            return
        }

        do {
            let audioURL: URL
            if entry.isBundled == true {
                guard let bundledURL = bundledProvider.audioURL(fileName: audioFileName) else {
                    errorMessage = "未在应用资源中找到该音频文件。"
                    return
                }
                audioURL = bundledURL
            } else {
                audioURL = try fileStore.audioFileURL(fileName: audioFileName)
            }
            try audioPlaybackController.toggle(entryID: entryID, url: audioURL)
            syncListeningState()
            updatePlaybackProgressTask()
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
        }
    }

    func stopListening() {
        playbackProgressTask?.cancel()
        playbackProgressTask = nil
        audioPlaybackController.stop()
        syncListeningState()
    }

    func seekListening(entryID: UUID, progress: Double) {
        guard currentListeningEntryID == entryID else { return }
        audioPlaybackController.seek(toProgress: progress)
        syncListeningState()
    }

    func isListeningPlaying(entryID: UUID) -> Bool {
        currentListeningEntryID == entryID && isCurrentListeningPlaying
    }

    private func syncListeningState() {
        currentListeningEntryID = audioPlaybackController.currentEntryID
        if let currentListeningEntryID {
            isCurrentListeningPlaying = audioPlaybackController.isPlaying(
                entryID: currentListeningEntryID)
            listeningCurrentTime = audioPlaybackController.currentTime
            listeningDuration = audioPlaybackController.duration
        } else {
            isCurrentListeningPlaying = false
            listeningCurrentTime = 0
            listeningDuration = 0
        }
    }

    private func updatePlaybackProgressTask() {
        playbackProgressTask?.cancel()
        playbackProgressTask = nil

        guard isCurrentListeningPlaying else { return }

        playbackProgressTask = Task { @MainActor [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.isCurrentListeningPlaying else { return }
                self.syncListeningState()
            }
        }
    }
}
