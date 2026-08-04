import Foundation

public struct SongLibraryBootstrapSnapshot: Equatable, Sendable {
    public let index: SongLibraryIndex
    public let bundledEntries: [SongLibraryEntry]

    public init(index: SongLibraryIndex, bundledEntries: [SongLibraryEntry]) {
        self.index = index
        self.bundledEntries = bundledEntries
    }
}

public protocol SongLibraryBootstrapLoading: Actor {
    func load() async -> SongLibraryBootstrapSnapshot?
}

public actor LiveSongLibraryBootstrapLoader: SongLibraryBootstrapLoading {
    private let transactionRecovery: any SongLibraryImportTransactionRecovering
    private let indexStore: any SongLibraryIndexStoreProtocol
    private let bundledProvider: any BundledSongLibraryProviderProtocol

    public init(
        transactionRecovery: any SongLibraryImportTransactionRecovering,
        indexStore: any SongLibraryIndexStoreProtocol,
        bundledProvider: any BundledSongLibraryProviderProtocol
    ) {
        self.transactionRecovery = transactionRecovery
        self.indexStore = indexStore
        self.bundledProvider = bundledProvider
    }

    public func load() async -> SongLibraryBootstrapSnapshot? {
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
