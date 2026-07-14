import Foundation

struct SongLibraryBootstrapFailure: Equatable, Sendable {
    let message: String
}

enum SongLibraryBootstrapSnapshot: Equatable, Sendable {
    case loaded(index: SongLibraryIndex, bundledEntries: [SongLibraryEntry])
    case blocked(failure: SongLibraryBootstrapFailure)
}

protocol SongLibraryBootstrapLoading: Actor {
    func load() async -> SongLibraryBootstrapSnapshot
}

actor LiveSongLibraryBootstrapLoader: SongLibraryBootstrapLoading {
    private let indexStore: any SongLibraryIndexStoreProtocol
    private let bundledProvider: any BundledSongLibraryProviderProtocol

    init(
        indexStore: any SongLibraryIndexStoreProtocol,
        bundledProvider: any BundledSongLibraryProviderProtocol
    ) {
        self.indexStore = indexStore
        self.bundledProvider = bundledProvider
    }

    func load() async -> SongLibraryBootstrapSnapshot {
        do {
            return .loaded(
                index: try await indexStore.load(),
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
