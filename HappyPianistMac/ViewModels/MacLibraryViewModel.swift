import Diagnostics
import Foundation
import Library
import Observation
import Practice

enum MacLibraryLoadState: Equatable {
    case idle
    case loading
    case ready
    case recoveryBlocked(String)
    case unavailable
}

@MainActor
@Observable
final class MacLibraryViewModel {
    private let indexStore: any SongLibraryIndexStoreProtocol
    private let importTransactionService: any SongLibraryImportTransactionServicing
    private let fileStore: any SongFileStoreProtocol
    private let audioImportService: any AudioImportServiceProtocol
    private let bundledProvider: any BundledSongLibraryProviderProtocol
    private let audioPlaybackController: SongAudioPlaybackStateController
    private let progressRepository: any PracticeProgressRepositoryProtocol
    private let diagnosticsReporter: any DiagnosticsReporting
    private var importQueue: [SongLibraryImportBatchItem] = []
    private var importQueueIndex = 0
    @ObservationIgnored private var audioIntentGeneration = 0
    @ObservationIgnored private var pendingAudioBindingEntryID: UUID?

    private(set) var entries: [SongLibraryEntry] = []
    var selectedEntryID: UUID?
    private(set) var loadState: MacLibraryLoadState = .idle
    private(set) var importState: SongLibraryImportState = .idle
    var isMusicXMLImporterPresented = false
    var isAudioImporterPresented = false
    private(set) var currentListeningEntryID: UUID?
    private(set) var isCurrentListeningPlaying = false
    private(set) var errorMessage: String?

    init(
        indexStore: any SongLibraryIndexStoreProtocol,
        importTransactionService: any SongLibraryImportTransactionServicing,
        fileStore: any SongFileStoreProtocol,
        audioImportService: any AudioImportServiceProtocol,
        bundledProvider: any BundledSongLibraryProviderProtocol,
        audioPlayer: SongAudioPlayerProtocol,
        progressRepository: any PracticeProgressRepositoryProtocol,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        self.indexStore = indexStore
        self.importTransactionService = importTransactionService
        self.fileStore = fileStore
        self.audioImportService = audioImportService
        self.bundledProvider = bundledProvider
        self.progressRepository = progressRepository
        self.diagnosticsReporter = diagnosticsReporter
        audioPlaybackController = SongAudioPlaybackStateController(player: audioPlayer)
        audioPlaybackController.onStateChanged = { [weak self] _ in
            self?.syncListeningState()
        }
    }

    func loadLibrary() async {
        guard loadState != .loading else { return }
        errorMessage = nil
        loadState = .loading
        switch await importTransactionService.recoverPendingTransactions() {
        case .recovered:
            do {
                if let initialSelection = install(try await indexStore.load()) {
                    await persistSelection(initialSelection)
                }
                loadState = .ready
            } catch {
                loadState = .unavailable
                errorMessage = "无法读取曲库，请重试。"
            }
        case let .blocked(blocked):
            loadState = .recoveryBlocked(blocked.message)
        }
    }

    func presentMusicXMLImporter() {
        guard importState.isActive == false else { return }
        isMusicXMLImporterPresented = true
    }

    func receiveImporterFailure() {
        errorMessage = "无法选择曲谱，请重试。"
    }

    func importMusicXML(from selectedURLs: [URL]) async {
        guard selectedURLs.isEmpty == false, importState.isActive == false else { return }
        errorMessage = nil
        importState = .staging(count: selectedURLs.count)
        let batch = await importTransactionService.stageImports(from: selectedURLs)
        guard let blocked = batch.blocked else {
            importQueue = batch.items
            importQueueIndex = 0
            await processNextImport()
            return
        }
        importState = .idle
        errorMessage = blocked.message
    }

    func confirmPendingImport(operationID: UUID) async {
        guard case let .awaitingConfirmation(pending, position, count) = importState,
              pending.id == operationID,
              case let .staged(descriptor)? = currentImportItem,
              descriptor.id == operationID
        else { return }

        importState = .processing(operationID: operationID, index: position, count: count)
        await handle(
            await importTransactionService.confirm(operationID: operationID),
            descriptor: descriptor,
            position: position,
            count: count
        )
        guard importState == .processing(operationID: operationID, index: position, count: count) else { return }
        await processNextImport()
    }

    func cancelPendingImport(operationID: UUID) async {
        guard case let .awaitingConfirmation(pending, _, _) = importState,
              pending.id == operationID,
              await importTransactionService.cancel(operationID: operationID)
        else {
            errorMessage = "无法安全取消当前导入，请重新启动后恢复。"
            return
        }
        importQueueIndex += 1
        await processNextImport()
    }

    func continueAfterImportFailure() async {
        guard case .itemFailure = importState else { return }
        if case let .staged(descriptor)? = currentImportItem,
           await importTransactionService.cancel(operationID: descriptor.id) == false
        {
            errorMessage = "无法安全清理当前导入，请重新启动后恢复。"
            return
        }
        importQueueIndex += 1
        await processNextImport()
    }

    func selectEntry(_ entryID: UUID) async {
        guard entries.contains(where: { $0.id == entryID }) else { return }
        stopListening()
        selectedEntryID = entryID
        await persistSelection(entryID)
    }

    func presentAudioImporter(for entryID: UUID) {
        guard entry(for: entryID)?.isBundled != true else {
            errorMessage = "内置曲目不支持绑定外部音频文件。"
            return
        }
        pendingAudioBindingEntryID = entryID
        isAudioImporterPresented = true
    }

    func receiveAudioImporterFailure() {
        pendingAudioBindingEntryID = nil
        errorMessage = "无法选择音频文件，请重试。"
    }

    func importAudio(from selectedURLs: [URL]) async {
        guard selectedURLs.count == 1, let entryID = pendingAudioBindingEntryID else { return }
        pendingAudioBindingEntryID = nil
        await bindAudio(entryID: entryID, from: selectedURLs[0])
    }

    func bindAudio(entryID: UUID, from sourceURL: URL) async {
        guard let targetEntry = entry(for: entryID) else { return }
        guard targetEntry.isBundled != true else {
            errorMessage = "内置曲目不支持绑定外部音频文件。"
            return
        }
        guard AudioImportService.isSupported(sourceURL) else {
            errorMessage = "仅支持导入 mp3 或 m4a 音频文件。"
            return
        }

        audioIntentGeneration += 1
        let generation = audioIntentGeneration
        do {
            let importedAudioFileName = try await audioImportService.importAudio(from: sourceURL)
            guard generation == audioIntentGeneration,
                  let currentEntry = entry(for: entryID),
                  currentEntry.audioFileName == targetEntry.audioFileName
            else {
                try? await fileStore.deleteAudioFile(named: importedAudioFileName)
                return
            }

            do {
                let mutation = try await indexStore.updateAudioFileName(
                    entryID: entryID,
                    expectedCurrentFileName: targetEntry.audioFileName,
                    newFileName: importedAudioFileName
                )
                guard generation == audioIntentGeneration else {
                    try? await fileStore.deleteAudioFile(named: importedAudioFileName)
                    return
                }
                guard case let .applied(index, _) = mutation else {
                    _ = install(mutation.index)
                    try? await fileStore.deleteAudioFile(named: importedAudioFileName)
                    errorMessage = "曲目已发生变化，请重试导入音频。"
                    return
                }
                if currentListeningEntryID == entryID {
                    stopListening()
                }
                _ = install(index)
                if let previousAudioFileName = targetEntry.audioFileName {
                    try? await fileStore.deleteAudioFile(named: previousAudioFileName)
                }
            } catch {
                try? await fileStore.deleteAudioFile(named: importedAudioFileName)
                throw error
            }
        } catch {
            guard generation == audioIntentGeneration else { return }
            errorMessage = "导入音频失败：\(error.localizedDescription)"
        }
    }

    func toggleListening(entryID: UUID) async {
        guard let targetEntry = entry(for: entryID) else { return }
        guard let audioFileName = targetEntry.audioFileName else {
            if targetEntry.isBundled == true {
                errorMessage = "此内置曲目没有可播放的音频。"
            } else {
                presentAudioImporter(for: entryID)
            }
            return
        }

        audioIntentGeneration += 1
        let generation = audioIntentGeneration
        do {
            let audioURL: URL
            if targetEntry.isBundled == true {
                guard let bundledURL = bundledProvider.audioURL(fileName: audioFileName) else {
                    errorMessage = "未在应用资源中找到该音频文件。"
                    return
                }
                audioURL = bundledURL
            } else {
                audioURL = try await fileStore.audioFileURL(fileName: audioFileName)
            }
            guard generation == audioIntentGeneration,
                  entry(for: entryID)?.audioFileName == audioFileName
            else { return }
            try audioPlaybackController.toggle(entryID: entryID, url: audioURL)
            syncListeningState()
        } catch {
            guard generation == audioIntentGeneration,
                  entry(for: entryID)?.audioFileName == audioFileName
            else { return }
            errorMessage = "播放失败：\(error.localizedDescription)"
        }
    }

    func stopListening() {
        audioIntentGeneration += 1
        audioPlaybackController.stop()
        syncListeningState()
    }

    func isListeningPlaying(entryID: UUID) -> Bool {
        currentListeningEntryID == entryID && isCurrentListeningPlaying
    }

    func deleteEntry(entryID: UUID) async {
        guard importState.isActive == false else {
            errorMessage = "曲谱导入完成或取消后才能删除曲目。"
            return
        }
        guard let entry = entry(for: entryID), entry.isBundled != true else {
            errorMessage = "内置曲目无法删除。"
            return
        }

        stopListening()
        do {
            let fallbackID = entries.last(where: { $0.id != entryID })?.id
            let mutation = try await indexStore.removeUserEntry(
                id: entryID,
                fallbackLastSelectedEntryID: fallbackID
            )
            guard case let .applied(index, removedEntry) = mutation else {
                _ = install(mutation.index)
                return
            }
            _ = install(index)

            var cleanupDiagnostic: DiagnosticEvent?
            do {
                try await progressRepository.remove(songID: removedEntry.id)
            } catch {
                errorMessage = "曲目已删除，但练习进度清理失败：\(error.localizedDescription)"
                cleanupDiagnostic = DiagnosticEvent(
                    severity: .warning,
                    code: .libraryPracticeHistoryCleanupFailed,
                    category: .library,
                    stage: "practiceHistoryCleanup",
                    summary: "删除曲目后无法清理练习历史",
                    reason: PracticePreparationErrorDetails.safeErrorSummary(error),
                    songID: removedEntry.id,
                    scoreFileVersionID: removedEntry.scoreFileVersionID,
                    persistence: .exportable
                )
            }

            do {
                try await fileStore.deleteScoreFile(named: removedEntry.musicXMLFileName)
                if let audioFileName = removedEntry.audioFileName {
                    try await fileStore.deleteAudioFile(named: audioFileName)
                }
            } catch {
                errorMessage = "曲目已从索引移除，但文件删除失败：\(error.localizedDescription)"
            }
            if let cleanupDiagnostic {
                _ = await diagnosticsReporter.record(cleanupDiagnostic)
            }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    private func persistSelection(_ entryID: UUID) async {
        do {
            _ = install(try await indexStore.setLastSelectedEntryID(entryID))
        } catch {
            errorMessage = "无法保存曲目选择，请重试。"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private var currentImportItem: SongLibraryImportBatchItem? {
        importQueue.indices.contains(importQueueIndex) ? importQueue[importQueueIndex] : nil
    }

    private func processNextImport() async {
        while let item = currentImportItem {
            let position = importQueueIndex + 1
            let count = importQueue.count
            switch item {
            case let .failure(failure):
                importState = .itemFailure(failure, index: position, count: count)
                return
            case let .staged(descriptor):
                importState = .processing(operationID: descriptor.id, index: position, count: count)
                await handle(
                    await importTransactionService.process(operationID: descriptor.id),
                    descriptor: descriptor,
                    position: position,
                    count: count
                )
                guard importState == .processing(
                    operationID: descriptor.id,
                    index: position,
                    count: count
                ) else { return }
            }
        }
        importQueue = []
        importQueueIndex = 0
        importState = .idle
    }

    private func handle(
        _ result: SongLibraryImportProcessResult,
        descriptor: SongLibraryStagedImport,
        position: Int,
        count: Int
    ) async {
        switch result {
        case let .committed(index, _):
            if let initialSelection = install(index) {
                await persistSelection(initialSelection)
            }
            importQueueIndex += 1
        case let .requiresConfirmation(pending):
            importState = .awaitingConfirmation(pending, index: position, count: count)
        case let .itemFailure(failure):
            importState = .itemFailure(failure, index: position, count: count)
        case let .blocked(blocked):
            importState = .itemFailure(
                SongLibraryImportItemFailure(fileName: descriptor.fileName, message: blocked.message),
                index: position,
                count: count
            )
        }
    }

    private func install(_ index: SongLibraryIndex) -> UUID? {
        entries = index.entries + bundledProvider.bundledEntries()
        if let lastSelectedEntryID = index.lastSelectedEntryID,
           entries.contains(where: { $0.id == lastSelectedEntryID })
        {
            selectedEntryID = lastSelectedEntryID
            return nil
        } else if selectedEntryID.map({ selectedEntryID in entries.contains(where: { $0.id == selectedEntryID }) }) != true {
            selectedEntryID = nil
            return entries.first?.id
        }
        return nil
    }

    private func entry(for entryID: UUID) -> SongLibraryEntry? {
        entries.first(where: { $0.id == entryID })
    }

    private func syncListeningState() {
        currentListeningEntryID = audioPlaybackController.currentEntryID
        if let currentListeningEntryID {
            isCurrentListeningPlaying = audioPlaybackController.isPlaying(entryID: currentListeningEntryID)
        } else {
            isCurrentListeningPlaying = false
        }
    }
}
