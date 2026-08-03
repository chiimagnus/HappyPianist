import Diagnostics
import Foundation
import Library
import MIDI

@MainActor
struct MacAppGraph {
    let songLibraryViewModel: MacLibraryViewModel
    let midiSettingsViewModel: MIDISettingsViewModel
    let midiOutputService: any MIDIOutputSendingProtocol
    let songLibraryEntryResolver: any SongLibraryEntryResolving
    let practiceProgressRepository: FilePracticeProgressRepository

    init(
        songLibraryViewModel: MacLibraryViewModel,
        midiSettingsViewModel: MIDISettingsViewModel,
        midiOutputService: any MIDIOutputSendingProtocol,
        songLibraryEntryResolver: any SongLibraryEntryResolving,
        practiceProgressRepository: FilePracticeProgressRepository
    ) {
        self.songLibraryViewModel = songLibraryViewModel
        self.midiSettingsViewModel = midiSettingsViewModel
        self.midiOutputService = midiOutputService
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
        let outputService = CoreMIDIOutputService(diagnosticsReporter: diagnosticsReporter)
        let midiSettingsViewModel = MIDISettingsViewModel(
            settingsStore: UserDefaultsMIDIEndpointSettingsStore(),
            inputEndpointDiscovery: {
                CoreMIDIInputEventSourceService().availableSources()
            },
            outputEndpointDiscovery: {
                outputService.listDestinations()
            },
            makeInputService: { endpointUniqueID in
                CoreMIDIInputEventSourceService(
                    selection: .endpointUniqueID(endpointUniqueID),
                    diagnosticsReporter: diagnosticsReporter
                )
            },
            outputService: outputService
        )

        return Self(
            songLibraryViewModel: MacLibraryViewModel(
                indexStore: indexStore,
                importTransactionService: importTransactionService,
                bundledProvider: bundledProvider
            ),
            midiSettingsViewModel: midiSettingsViewModel,
            midiOutputService: outputService,
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
