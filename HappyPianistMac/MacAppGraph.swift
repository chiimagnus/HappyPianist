import Foundation
import Library

@MainActor
struct MacAppGraph {
    let bundledLibraryProvider: any BundledSongLibraryProviderProtocol
    let libraryEntryState: MacLibraryEntryState

    init(
        bundledLibraryProvider: any BundledSongLibraryProviderProtocol,
        libraryEntryState: MacLibraryEntryState = .empty
    ) {
        self.bundledLibraryProvider = bundledLibraryProvider
        self.libraryEntryState = libraryEntryState
    }

    static func make() -> Self {
        Self(bundledLibraryProvider: EmptyMacBundledSongLibraryProvider())
    }
}

enum MacLibraryEntryState: Equatable {
    case empty

    var message: String {
        "从本机选择 MusicXML 或 MXL 曲谱后开始练习。"
    }
}

private struct EmptyMacBundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry] { [] }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}
