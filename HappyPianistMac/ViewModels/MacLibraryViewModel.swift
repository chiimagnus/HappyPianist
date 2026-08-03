import Foundation
import Library
import Observation

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
    private let bundledProvider: any BundledSongLibraryProviderProtocol
    private var importQueue: [SongLibraryImportBatchItem] = []
    private var importQueueIndex = 0

    private(set) var entries: [SongLibraryEntry] = []
    var selectedEntryID: UUID?
    private(set) var loadState: MacLibraryLoadState = .idle
    private(set) var importState: SongLibraryImportState = .idle
    var isMusicXMLImporterPresented = false
    private(set) var errorMessage: String?

    init(
        indexStore: any SongLibraryIndexStoreProtocol,
        importTransactionService: any SongLibraryImportTransactionServicing,
        bundledProvider: any BundledSongLibraryProviderProtocol
    ) {
        self.indexStore = indexStore
        self.importTransactionService = importTransactionService
        self.bundledProvider = bundledProvider
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
        await persistSelection(entryID)
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
}
