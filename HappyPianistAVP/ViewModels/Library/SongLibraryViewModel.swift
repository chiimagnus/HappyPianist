import Foundation
import Observation

@MainActor
@Observable
final class SongLibraryViewModel {
    private let indexStore: SongLibraryIndexStoreProtocol
    private let importTransactionService: any SongLibraryImportTransactionServicing
    private let fileStore: SongFileStoreProtocol
    private let audioImportService: AudioImportServiceProtocol
    private let bundledProvider: BundledSongLibraryProviderProtocol
    private let bootstrapLoader: (any SongLibraryBootstrapLoading)?
    private var bundledEntries: [SongLibraryEntry]
    private let audioPlaybackController: SongAudioPlaybackStateController
    private let practiceProgressRepository: any PracticeProgressRepositoryProtocol
    private let diagnosticsReporter: any DiagnosticsReporting
    private let snapshotBuilder: any SongPracticeLibrarySnapshotBuilding
    private let snapshotSleeper: any SleeperProtocol
    private let snapshotSettleDelay: Duration
    private let selectionPersistenceSleeper: any SleeperProtocol
    private let selectionPersistenceDelay: Duration
    @ObservationIgnored private var playbackProgressTask: Task<Void, Never>?
    @ObservationIgnored private var listenIntentGeneration = 0
    @ObservationIgnored private var selectionPersistenceDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var selectionPersistenceWorker: Task<Void, Never>?
    @ObservationIgnored private var selectionPersistenceRevision = 0
    @ObservationIgnored private var selectionPersistenceReadyRevision = 0
    @ObservationIgnored private var selectionPersistenceFailedRevision: Int?
    @ObservationIgnored private var selectionPersistenceNeedsDrain = false
    @ObservationIgnored private var snapshotLoadTask: Task<Void, Never>?
    @ObservationIgnored private var snapshotGeneration = 0
    @ObservationIgnored private var importQueue: [SongLibraryImportBatchItem] = []
    @ObservationIgnored private var importQueueIndex = 0
    @ObservationIgnored private var importQueueGeneration = 0
    private var desiredPersistedSelection: UUID?
    private var persistedSelection: UUID?

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
    private(set) var importState: SongLibraryImportState = .idle
    private(set) var selectedEntryID: UUID?
    private(set) var practiceSnapshotState: SongPracticeLibraryPresentationState = .noSelection

    init(
        indexStore: SongLibraryIndexStoreProtocol,
        importTransactionService: any SongLibraryImportTransactionServicing,
        fileStore: SongFileStoreProtocol,
        audioImportService: AudioImportServiceProtocol,
        bundledProvider: BundledSongLibraryProviderProtocol,
        audioPlayer: SongAudioPlayerProtocol,
        practiceProgressRepository: any PracticeProgressRepositoryProtocol,
        diagnosticsReporter: any DiagnosticsReporting,
        snapshotBuilder: any SongPracticeLibrarySnapshotBuilding = SongPracticeLibrarySnapshotBuilder(),
        bootstrapLoader: (any SongLibraryBootstrapLoading)? = nil,
        initialSnapshot: SongLibraryBootstrapSnapshot? = nil,
        snapshotSleeper: any SleeperProtocol = TaskSleeper(),
        snapshotSettleDelay: Duration = .milliseconds(150),
        selectionPersistenceSleeper: any SleeperProtocol = TaskSleeper(),
        selectionPersistenceDelay: Duration = .milliseconds(200)
    ) {
        self.indexStore = indexStore
        self.importTransactionService = importTransactionService
        self.fileStore = fileStore
        self.audioImportService = audioImportService
        self.bundledProvider = bundledProvider
        self.bootstrapLoader = bootstrapLoader
        self.practiceProgressRepository = practiceProgressRepository
        self.diagnosticsReporter = diagnosticsReporter
        self.snapshotBuilder = snapshotBuilder
        self.snapshotSleeper = snapshotSleeper
        self.snapshotSettleDelay = snapshotSettleDelay
        self.selectionPersistenceSleeper = selectionPersistenceSleeper
        self.selectionPersistenceDelay = selectionPersistenceDelay
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
        if hasLoadedLibrary {
            installBootstrapSelection()
        }

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
            installBootstrapSelection()
        case let .blocked(failure):
            bootstrapFailureMessage = failure.message
        }
        isLibraryLoading = false
    }

    func reload() async {
        do {
            index = try await indexStore.load()
            installBootstrapSelection()
        } catch {
            errorMessage = "加载乐曲库失败：\(error.localizedDescription)"
        }
    }

    func refreshSelectedPracticeSnapshot() {
        scheduleSnapshotLoad()
    }

    func flushPendingSelectionPersistence() async {
        selectionPersistenceDebounceTask?.cancel()
        selectionPersistenceDebounceTask = nil
        selectionPersistenceReadyRevision = selectionPersistenceRevision
        selectionPersistenceFailedRevision = nil

        while selectionPersistenceNeedsDrain {
            startSelectionPersistenceWorkerIfNeeded()
            guard let worker = selectionPersistenceWorker else { return }
            await worker.value
            if selectionPersistenceFailedRevision == selectionPersistenceRevision {
                return
            }
        }
    }

    private func installBootstrapSelection() {
        let availableEntries = entries
        let resolvedSelection = index.lastSelectedEntryID.flatMap { preferredID in
            availableEntries.contains(where: { $0.id == preferredID }) ? preferredID : nil
        } ?? availableEntries.first?.id

        selectionPersistenceDebounceTask?.cancel()
        selectionPersistenceDebounceTask = nil
        selectionPersistenceRevision += 1
        selectionPersistenceReadyRevision = selectionPersistenceRevision
        selectionPersistenceFailedRevision = nil
        selectedEntryID = resolvedSelection
        persistedSelection = index.lastSelectedEntryID
        desiredPersistedSelection = resolvedSelection
        selectionPersistenceNeedsDrain = resolvedSelection != index.lastSelectedEntryID
        if selectionPersistenceNeedsDrain {
            requestSelectionPersistence(resolvedSelection)
        }
        scheduleSnapshotLoad()
    }

    private func adoptPersistedSelection(_ entryID: UUID?) {
        selectionPersistenceDebounceTask?.cancel()
        selectionPersistenceDebounceTask = nil
        selectionPersistenceRevision += 1
        selectionPersistenceReadyRevision = selectionPersistenceRevision
        selectionPersistenceFailedRevision = nil
        selectedEntryID = entryID
        persistedSelection = entryID
        desiredPersistedSelection = entryID
        selectionPersistenceNeedsDrain = false
        scheduleSnapshotLoad()
    }

    private func requestSelectionPersistence(_ entryID: UUID?) {
        desiredPersistedSelection = entryID
        selectionPersistenceRevision += 1
        selectionPersistenceNeedsDrain = persistedSelection != entryID || selectionPersistenceWorker != nil
        selectionPersistenceFailedRevision = nil
        let revision = selectionPersistenceRevision

        selectionPersistenceDebounceTask?.cancel()
        guard selectionPersistenceNeedsDrain else {
            selectionPersistenceDebounceTask = nil
            return
        }
        selectionPersistenceDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await selectionPersistenceSleeper.sleep(for: selectionPersistenceDelay)
                try Task.checkCancellation()
            } catch {
                return
            }
            guard revision == selectionPersistenceRevision else { return }
            selectionPersistenceReadyRevision = revision
            selectionPersistenceDebounceTask = nil
            startSelectionPersistenceWorkerIfNeeded()
        }
    }

    private func startSelectionPersistenceWorkerIfNeeded() {
        guard selectionPersistenceWorker == nil,
              selectionPersistenceNeedsDrain,
              selectionPersistenceReadyRevision == selectionPersistenceRevision
        else { return }

        selectionPersistenceWorker = Task { @MainActor [weak self] in
            await self?.drainSelectionPersistence()
        }
    }

    private func drainSelectionPersistence() async {
        while selectionPersistenceNeedsDrain,
              selectionPersistenceReadyRevision == selectionPersistenceRevision
        {
            let revision = selectionPersistenceRevision
            let target = desiredPersistedSelection
            do {
                let updatedIndex = try await indexStore.setLastSelectedEntryID(target)
                persistedSelection = target
                if revision == selectionPersistenceRevision {
                    index = updatedIndex
                }
                selectionPersistenceNeedsDrain = desiredPersistedSelection != persistedSelection
            } catch {
                selectionPersistenceNeedsDrain = desiredPersistedSelection != persistedSelection
                if revision == selectionPersistenceRevision {
                    selectionPersistenceFailedRevision = revision
                    errorMessage = "保存曲库选择失败：\(error.localizedDescription)"
                }
                break
            }
        }

        selectionPersistenceWorker = nil
        if selectionPersistenceFailedRevision != selectionPersistenceRevision {
            startSelectionPersistenceWorkerIfNeeded()
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func didTapImportMusicXML() {
        guard importState.isActive == false else { return }
        isMusicXMLImporterPresented = true
    }

    func importMusicXML(from selectedURLs: [URL]) async {
        guard selectedURLs.isEmpty == false, importState.isActive == false else { return }
        importQueueGeneration += 1
        let generation = importQueueGeneration
        importState = .staging(index: 0, count: selectedURLs.count)
        let batch = await importTransactionService.stageImports(from: selectedURLs)
        guard generation == importQueueGeneration else {
            for item in batch.items {
                guard case let .staged(descriptor) = item else { continue }
                _ = await importTransactionService.cancel(operationID: descriptor.id)
            }
            return
        }
        if let blocked = batch.blocked {
            importState = .idle
            errorMessage = blocked.message
            return
        }

        importQueue = batch.items
        importQueueIndex = 0
        await drainImportQueue(generation: generation)
    }

    func cancelPendingImport(operationID: UUID) async {
        guard case let .awaitingConfirmation(pending, _, _) = importState,
              pending.id == operationID,
              case let .staged(descriptor) = currentImportQueueItem,
              descriptor.id == operationID
        else { return }
        let generation = importQueueGeneration
        guard await importTransactionService.cancel(operationID: operationID) else {
            errorMessage = "无法安全取消当前导入，请重新启动后恢复。"
            return
        }
        guard generation == importQueueGeneration else { return }
        importQueueIndex += 1
        await drainImportQueue(generation: generation)
    }

    func confirmPendingImport(operationID: UUID) async {
        guard case let .awaitingConfirmation(pending, position, count) = importState,
              pending.id == operationID,
              case let .staged(descriptor) = currentImportQueueItem,
              descriptor.id == operationID
        else { return }
        let generation = importQueueGeneration
        importState = .processing(
            operationID: operationID,
            index: position,
            count: count
        )
        let result = await importTransactionService.confirm(operationID: operationID)
        guard generation == importQueueGeneration else { return }
        guard handleImportResult(
            result,
            descriptor: descriptor,
            position: position,
            count: count
        ) else { return }
        importQueueIndex += 1
        await drainImportQueue(generation: generation)
    }

    func continueAfterImportFailure() async {
        guard case .itemFailure = importState,
              currentImportQueueItem != nil
        else { return }
        let generation = importQueueGeneration
        if case let .staged(descriptor) = currentImportQueueItem {
            guard await importTransactionService.cancel(operationID: descriptor.id) else {
                errorMessage = "无法安全清理当前导入，请重新启动后恢复。"
                return
            }
            do {
                index = try await indexStore.load()
                repairSelectionAfterImportReload()
            } catch {
                errorMessage = "清理导入后无法刷新曲库：\(error.localizedDescription)"
                return
            }
        }
        guard generation == importQueueGeneration else { return }
        importQueueIndex += 1
        await drainImportQueue(generation: generation)
    }

    func cancelAllImports() async {
        guard importState.isActive else { return }
        importQueueGeneration += 1
        let operationIDs = importQueue.dropFirst(importQueueIndex).compactMap { item -> UUID? in
            guard case let .staged(descriptor) = item else { return nil }
            return descriptor.id
        }
        var failedOperationIDs: [UUID] = []
        for operationID in operationIDs {
            if await importTransactionService.cancel(operationID: operationID) == false {
                failedOperationIDs.append(operationID)
            }
        }
        if let failedOperationID = failedOperationIDs.first {
            let descriptor = importQueue.compactMap { item -> SongLibraryStagedImport? in
                guard case let .staged(descriptor) = item,
                      descriptor.id == failedOperationID
                else { return nil }
                return descriptor
            }.first ?? SongLibraryStagedImport(id: failedOperationID, fileName: "未知曲谱")
            importQueue = [.staged(descriptor)]
            importQueueIndex = 0
            importState = .itemFailure(
                SongLibraryImportItemFailure(
                    fileName: descriptor.fileName,
                    message: "无法安全取消，请重新启动后恢复。"
                ),
                index: 1,
                count: 1
            )
            return
        }
        importQueue = []
        importQueueIndex = 0
        importState = .idle
        do {
            index = try await indexStore.load()
            repairSelectionAfterImportReload()
        } catch {
            errorMessage = "取消导入后无法刷新曲库：\(error.localizedDescription)"
        }
    }

    func startPractice(
        entryID: UUID,
        perform: @MainActor (UUID) -> Void
    ) {
        guard importState.isActive == false else {
            errorMessage = "曲谱导入完成或取消后才能开始练习。"
            return
        }
        guard entries.contains(where: { $0.id == entryID }) else { return }
        perform(entryID)
    }

    private var currentImportQueueItem: SongLibraryImportBatchItem? {
        importQueue.indices.contains(importQueueIndex) ? importQueue[importQueueIndex] : nil
    }

    private func drainImportQueue(generation: Int) async {
        while generation == importQueueGeneration,
              let item = currentImportQueueItem
        {
            let position = importQueueIndex + 1
            let count = importQueue.count
            switch item {
            case let .failure(failure):
                importState = .itemFailure(failure, index: position, count: count)
                return
            case let .staged(descriptor):
                importState = .processing(
                    operationID: descriptor.id,
                    index: position,
                    count: count
                )
                let result = await importTransactionService.process(operationID: descriptor.id)
                guard generation == importQueueGeneration else { return }
                guard handleImportResult(
                    result,
                    descriptor: descriptor,
                    position: position,
                    count: count
                ) else { return }
                importQueueIndex += 1
            }
        }
        guard generation == importQueueGeneration else { return }
        importQueue = []
        importQueueIndex = 0
        importState = .idle
    }

    private func handleImportResult(
        _ result: SongLibraryImportProcessResult,
        descriptor: SongLibraryStagedImport,
        position: Int,
        count: Int
    ) -> Bool {
        switch result {
        case let .committed(updatedIndex, entry):
            index = updatedIndex
            if selectedEntryID == nil {
                selectedEntryID = entry.id
                requestSelectionPersistence(entry.id)
            }
            scheduleSnapshotLoad()
            return true
        case let .requiresConfirmation(pending):
            importState = .awaitingConfirmation(pending, index: position, count: count)
            return false
        case let .itemFailure(failure):
            importState = .itemFailure(failure, index: position, count: count)
            return false
        case let .blocked(blocked):
            importState = .itemFailure(
                SongLibraryImportItemFailure(
                    fileName: descriptor.fileName,
                    message: blocked.message
                ),
                index: position,
                count: count
            )
            return false
        }
    }

    private func repairSelectionAfterImportReload() {
        guard let selectedEntryID,
              entries.contains(where: { $0.id == selectedEntryID })
        else {
            let replacement = entries.first?.id
            self.selectedEntryID = replacement
            requestSelectionPersistence(replacement)
            scheduleSnapshotLoad()
            return
        }
    }

    func selectEntry(_ entryID: UUID) {
        guard entries.contains(where: { $0.id == entryID }), selectedEntryID != entryID else { return }
        listenIntentGeneration += 1
        if currentListeningEntryID != nil {
            stopListening()
        }
        selectedEntryID = entryID
        requestSelectionPersistence(entryID)
        scheduleSnapshotLoad()
    }

    func deleteEntry(entryID: UUID) async {
        guard importState.isActive == false else {
            errorMessage = "曲谱导入完成或取消后才能删除曲目。"
            return
        }
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
            if selectedEntryID == entryID {
                adoptPersistedSelection(updatedIndex.lastSelectedEntryID)
            }

            do {
                try await practiceProgressRepository.remove(songID: entry.id)
            } catch {
                errorMessage = "曲目已删除，但练习进度清理失败：\(error.localizedDescription)"
            }

            do {
                try await fileStore.deleteScoreFile(named: entry.musicXMLFileName)
                if let audioFileName = entry.audioFileName {
                    try await fileStore.deleteAudioFile(named: audioFileName)
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
            let importedAudioFileName = try await audioImportService.importAudio(from: sourceURL)

            let previousAudioFileName = entry.audioFileName

            do {
                let mutation = try await indexStore.updateAudioFileName(
                    entryID: entryID,
                    expectedCurrentFileName: previousAudioFileName,
                    newFileName: importedAudioFileName
                )
                guard case let .applied(updatedIndex, _) = mutation else {
                    index = mutation.index
                    try? await fileStore.deleteAudioFile(named: importedAudioFileName)
                    errorMessage = "曲目已发生变化，请重试导入音频。"
                    return
                }
                if currentListeningEntryID == entryID {
                    stopListening()
                }
                index = updatedIndex
                if let previousAudioFileName {
                    try? await fileStore.deleteAudioFile(named: previousAudioFileName)
                }
            } catch {
                try? await fileStore.deleteAudioFile(named: importedAudioFileName)
                throw error
            }
        } catch {
            errorMessage = "导入音频失败：\(error.localizedDescription)"
        }
    }

    func didTapListen(entryID: UUID) async {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return
        }
        guard let audioFileName = entry.audioFileName else {
            errorMessage = "此曲目未绑定音频文件，可再次导入音频。"
            return
        }

        listenIntentGeneration += 1
        let generation = listenIntentGeneration
        do {
            let audioURL: URL
            if entry.isBundled == true {
                guard let bundledURL = bundledProvider.audioURL(fileName: audioFileName) else {
                    errorMessage = "未在应用资源中找到该音频文件。"
                    return
                }
                audioURL = bundledURL
            } else {
                audioURL = try await fileStore.audioFileURL(fileName: audioFileName)
            }
            guard generation == listenIntentGeneration,
                  entries.first(where: { $0.id == entryID })?.audioFileName == audioFileName
            else { return }
            try audioPlaybackController.toggle(entryID: entryID, url: audioURL)
            syncListeningState()
            updatePlaybackProgressTask()
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
        }
    }

    func stopListening() {
        listenIntentGeneration += 1
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

    private func scheduleSnapshotLoad() {
        snapshotLoadTask?.cancel()
        snapshotGeneration += 1
        let generation = snapshotGeneration

        guard let entry = selectedEntryID.flatMap({ selectedID in
            entries.first(where: { $0.id == selectedID })
        }) else {
            snapshotLoadTask = nil
            practiceSnapshotState = .noSelection
            return
        }

        let identity = SongPracticeLibrarySelectionIdentity(
            songID: entry.id,
            scoreFileVersionID: entry.scoreFileVersionID
        )
        practiceSnapshotState = .loading(identity)
        snapshotLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await snapshotSleeper.sleep(for: snapshotSettleDelay)
                try Task.checkCancellation()
            } catch {
                return
            }

            // ponytail: one JSON decode plus same-song linear filtering is intentional;
            // add an index/cache only after measured selection latency warrants invalidation complexity.
            let historyResult = await practiceProgressRepository.history(for: entry.id)
            guard Task.isCancelled == false else { return }
            let state: SongPracticeLibraryPresentationState
            var diagnosticEvent: DiagnosticEvent?
            switch historyResult {
            case let .loaded(history):
                switch await snapshotBuilder.build(entry: entry, history: history) {
                case .neverPracticed:
                    state = .neverPracticed(identity)
                case let .current(snapshot):
                    state = .current(snapshot)
                case let .needsRebuild(historyDate):
                    state = .needsRebuild(identity, historyDate: historyDate)
                }
            case .corrupted:
                state = .unavailable(identity)
                diagnosticEvent = DiagnosticEvent(
                    severity: .warning,
                    code: .libraryPracticeHistoryLoadFailed,
                    category: .library,
                    stage: "practiceHistoryLoad",
                    summary: "无法读取曲目练习历史",
                    reason: "token=\(identity.scoreFileVersionID?.uuidString ?? "legacy-nil"); repository=corrupted",
                    songID: identity.songID,
                    persistence: .exportable
                )
            }

            guard generation == snapshotGeneration,
                  selectedEntryID == identity.songID,
                  entries.first(where: { $0.id == identity.songID })?.scoreFileVersionID
                    == identity.scoreFileVersionID
            else { return }
            practiceSnapshotState = state
            snapshotLoadTask = nil
            if let diagnosticEvent {
                _ = await diagnosticsReporter.record(diagnosticEvent)
            }
        }
    }
}
