import Diagnostics
import Foundation
import Library

@MainActor
struct MacAppGraph {
    let songLibraryViewModel: MacLibraryViewModel
    let songLibraryEntryResolver: any SongLibraryEntryResolving
    let practiceProgressRepository: FilePracticeProgressRepository

    init(
        songLibraryViewModel: MacLibraryViewModel,
        songLibraryEntryResolver: any SongLibraryEntryResolving,
        practiceProgressRepository: FilePracticeProgressRepository
    ) {
        self.songLibraryViewModel = songLibraryViewModel
        self.songLibraryEntryResolver = songLibraryEntryResolver
        self.practiceProgressRepository = practiceProgressRepository
    }

    static func make() -> Self {
        let diagnosticsStore = FileDiagnosticsStore()
        let diagnosticsReporter: any DiagnosticsReporting = AppDiagnosticsReporter(
            exportStore: diagnosticsStore
        )
        let bundledProvider: any BundledSongLibraryProviderProtocol = EmptyMacBundledSongLibraryProvider()
        let indexStore = SongLibraryIndexStore()
        let fileStore = SongFileStore()
        let importTransactionService = SongLibraryImportTransactionService(
            indexStore: indexStore,
            diagnostics: diagnosticsReporter
        )
        let progressRepository = FilePracticeProgressRepository()

        return Self(
            songLibraryViewModel: MacLibraryViewModel(
                indexStore: indexStore,
                importTransactionService: importTransactionService,
                bundledProvider: bundledProvider
            ),
            songLibraryEntryResolver: SongLibraryEntryResolver(
                indexStore: indexStore,
                bundledProvider: bundledProvider,
                fileStore: fileStore
            ),
            practiceProgressRepository: progressRepository
        )
    }
}

private struct EmptyMacBundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry] { [] }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}
