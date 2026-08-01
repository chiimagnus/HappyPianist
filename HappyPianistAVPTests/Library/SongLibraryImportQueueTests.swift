import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func importQueueConfirmsOneOperationBeforeProcessingTheNext() async {
    let firstID = UUID()
    let secondID = UUID()
    let firstEntry = queueEntry(name: "first.musicxml")
    let secondEntry = queueEntry(name: "second.musicxml")
    let afterFirst = SongLibraryIndex(entries: [firstEntry])
    let finalIndex = SongLibraryIndex(entries: [firstEntry, secondEntry])
    let service = ImportQueueIntegrationService(
        stageBatches: [[
            .staged(SongLibraryStagedImport(id: firstID, fileName: "first.musicxml")),
            .staged(SongLibraryStagedImport(id: secondID, fileName: "second.musicxml")),
        ]],
        processResults: [
            firstID: .requiresConfirmation(
                SongLibraryPendingImport(
                    id: firstID,
                    fileName: "first.musicxml",
                    conflict: .filesystemOrphan
                )
            ),
            secondID: .committed(index: finalIndex, entry: secondEntry),
        ],
        confirmResults: [
            firstID: .committed(index: afterFirst, entry: firstEntry),
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(importTransactionService: service)

    await viewModel.importMusicXML(from: [
        URL(fileURLWithPath: "/tmp/first.musicxml"),
        URL(fileURLWithPath: "/tmp/second.musicxml"),
    ])
    #expect(await service.processedIDs == [firstID])

    await viewModel.confirmPendingImport(operationID: firstID)

    #expect(viewModel.importState == .idle)
    #expect(viewModel.index == finalIndex)
    #expect(await service.confirmedIDs == [firstID])
    #expect(await service.processedIDs == [firstID, secondID])
}

@MainActor
@Test
func staleImportCallbacksCannotAdvanceOrOverwriteANewerQueue() async {
    let oldID = UUID()
    let newID = UUID()
    let newEntry = queueEntry(name: "new.musicxml")
    let finalIndex = SongLibraryIndex(entries: [newEntry])
    let service = ImportQueueIntegrationService(
        stageBatches: [
            [.staged(SongLibraryStagedImport(id: oldID, fileName: "old.musicxml"))],
            [.staged(SongLibraryStagedImport(id: newID, fileName: "new.musicxml"))],
        ],
        processResults: [
            oldID: .requiresConfirmation(
                SongLibraryPendingImport(
                    id: oldID,
                    fileName: "old.musicxml",
                    conflict: .filesystemOrphan
                )
            ),
            newID: .committed(index: finalIndex, entry: newEntry),
        ],
        confirmResults: [
            oldID: .blocked(
                SongLibraryBlockedImport(operationID: oldID, message: "stale callback")
            ),
        ]
    )
    let viewModel = SongLibraryViewModelTestHarness.make(importTransactionService: service)
    await viewModel.importMusicXML(from: [URL(fileURLWithPath: "/tmp/old.musicxml")])
    await viewModel.cancelAllImports()
    await viewModel.importMusicXML(from: [URL(fileURLWithPath: "/tmp/new.musicxml")])

    await viewModel.confirmPendingImport(operationID: oldID)
    await viewModel.cancelPendingImport(operationID: oldID)

    #expect(viewModel.importState == .idle)
    #expect(viewModel.index == finalIndex)
    #expect(await service.confirmedIDs.isEmpty)
    #expect(await service.cancelledIDs == [oldID])
}

private actor ImportQueueIntegrationService: SongLibraryImportTransactionServicing {
    private var stageBatches: [[SongLibraryImportBatchItem]]
    private let processResults: [UUID: SongLibraryImportProcessResult]
    private let confirmResults: [UUID: SongLibraryImportProcessResult]
    private(set) var processedIDs: [UUID] = []
    private(set) var confirmedIDs: [UUID] = []
    private(set) var cancelledIDs: [UUID] = []

    init(
        stageBatches: [[SongLibraryImportBatchItem]],
        processResults: [UUID: SongLibraryImportProcessResult],
        confirmResults: [UUID: SongLibraryImportProcessResult]
    ) {
        self.stageBatches = stageBatches
        self.processResults = processResults
        self.confirmResults = confirmResults
    }

    func recoverPendingTransactions() -> SongLibraryTransactionRecoveryResult {
        .recovered
    }

    func stageImports(from _: [URL]) -> SongLibraryImportBatchStageResult {
        SongLibraryImportBatchStageResult(
            items: stageBatches.isEmpty ? [] : stageBatches.removeFirst(),
            blocked: nil
        )
    }

    func process(operationID: UUID) -> SongLibraryImportProcessResult {
        processedIDs.append(operationID)
        return processResults[operationID]
            ?? .blocked(SongLibraryBlockedImport(operationID: operationID, message: "missing process result"))
    }

    func confirm(operationID: UUID) -> SongLibraryImportProcessResult {
        confirmedIDs.append(operationID)
        return confirmResults[operationID]
            ?? .blocked(SongLibraryBlockedImport(operationID: operationID, message: "missing confirm result"))
    }

    func cancel(operationID: UUID) -> Bool {
        guard cancelledIDs.contains(operationID) == false else { return true }
        cancelledIDs.append(operationID)
        return true
    }
}

private func queueEntry(name: String) -> SongLibraryEntry {
    SongLibraryEntry(
        id: UUID(),
        displayName: URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent,
        musicXMLFileName: name,
        scoreFileVersionID: UUID(),
        importedAt: .distantPast,
        audioFileName: nil
    )
}
