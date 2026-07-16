import Foundation

struct SongLibraryBootstrapFailure: Equatable {
    let message: String
}

enum SongLibraryBootstrapSnapshot: Equatable {
    case loaded(index: SongLibraryIndex, bundledEntries: [SongLibraryEntry])
    case blocked(failure: SongLibraryBootstrapFailure)
}

protocol SongLibraryBootstrapLoading: Actor {
    func load() async -> SongLibraryBootstrapSnapshot
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

    func load() async -> SongLibraryBootstrapSnapshot {
        let recoveryResult = await transactionRecovery.recoverPendingTransactions()
        if case let .blocked(blocked) = recoveryResult {
            return .blocked(failure: SongLibraryBootstrapFailure(message: blocked.message))
        }
        do {
            return try await .loaded(
                index: indexStore.load(),
                bundledEntries: bundledProvider.bundledEntries()
            )
        } catch {
            return .blocked(
                failure: SongLibraryBootstrapFailure(
                    message: "加载乐曲库失败：\(error.localizedDescription)"
                )
            )
        }
    }
}
