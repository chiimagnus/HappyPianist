import Foundation

struct SongLibraryBootstrapSnapshot: Equatable {
    let index: SongLibraryIndex
    let bundledEntries: [SongLibraryEntry]
}

protocol SongLibraryBootstrapLoading: Actor {
    func load() async -> SongLibraryBootstrapSnapshot?
}

actor LiveSongLibraryBootstrapLoader: SongLibraryBootstrapLoading {
    private let transactionRecovery: any SongLibraryImportTransactionRecovering
    private let indexStore: any SongLibraryIndexStoreProtocol
    private let bundledProvider: any BundledSongLibraryProviderProtocol

    init(
        transactionRecovery: any SongLibraryImportTransactionRecovering,
        indexStore: any SongLibraryIndexStoreProtocol,
        bundledProvider: any BundledSongLibraryProviderProtocol
    ) {
        self.transactionRecovery = transactionRecovery
        self.indexStore = indexStore
        self.bundledProvider = bundledProvider
    }

    func load() async -> SongLibraryBootstrapSnapshot? {
        let recoveryResult = await transactionRecovery.recoverPendingTransactions()
        guard case .recovered = recoveryResult else { return nil }
        do {
            return try await SongLibraryBootstrapSnapshot(
                index: indexStore.load(),
                bundledEntries: bundledProvider.bundledEntries()
            )
        } catch {
            return nil
        }
    }
}
