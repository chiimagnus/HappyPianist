import Diagnostics
import Foundation
import Library
import MIDI
import Practice

@MainActor
struct MacAppGraph {
    let songLibraryViewModel: MacLibraryViewModel
    let midiSettingsViewModel: MIDISettingsViewModel
    let practiceViewModel: MacPracticeViewModel
    let midiOutputService: any MIDIOutputSendingProtocol
    let songLibraryEntryResolver: any SongLibraryEntryResolving
    let practiceProgressRepository: FilePracticeProgressRepository

    init(
        songLibraryViewModel: MacLibraryViewModel,
        midiSettingsViewModel: MIDISettingsViewModel,
        practiceViewModel: MacPracticeViewModel,
        midiOutputService: any MIDIOutputSendingProtocol,
        songLibraryEntryResolver: any SongLibraryEntryResolving,
        practiceProgressRepository: FilePracticeProgressRepository
    ) {
        self.songLibraryViewModel = songLibraryViewModel
        self.midiSettingsViewModel = midiSettingsViewModel
        self.practiceViewModel = practiceViewModel
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
        let preparationService: any PracticePreparationServiceProtocol = PracticePreparationService(
            diagnosticsReporter: diagnosticsReporter
        )
        let sessionRecorder = PracticeSessionRecorder(
            repository: progressRepository,
            diagnosticsReporter: diagnosticsReporter,
            performanceAnalyzer: PracticePerformanceAnalyzer(diagnosticsReporter: diagnosticsReporter)
        )
        let entryResolver = SongLibraryEntryResolver(
            indexStore: indexStore,
            bundledProvider: bundledProvider,
            fileStore: fileStore
        )
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
            practiceViewModel: MacPracticeViewModel(
                resolveEntry: { songID in
                    await entryResolver.resolve(songID: songID)
                },
                preparationService: preparationService,
                progressRepository: progressRepository,
                progressRecovery: progressRepository,
                sessionRecorder: sessionRecorder,
                midiSettingsViewModel: midiSettingsViewModel,
                makeReferencePlaybackService: { endpointUniqueID in
                    CoreMIDIPracticePlaybackService(
                        destinationUniqueID: endpointUniqueID,
                        outputService: outputService,
                        diagnosticsReporter: diagnosticsReporter
                    )
                },
                diagnosticsReporter: diagnosticsReporter
            ),
            midiOutputService: outputService,
            songLibraryEntryResolver: entryResolver,
            practiceProgressRepository: progressRepository
        )
    }
}

private struct EmptyMacBundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry] { [] }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}
