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
    let diagnosticsViewModel: DiagnosticsViewModel

    init(
        songLibraryViewModel: MacLibraryViewModel,
        midiSettingsViewModel: MIDISettingsViewModel,
        diagnosticsViewModel: DiagnosticsViewModel,
        practiceViewModel: MacPracticeViewModel
    ) {
        self.songLibraryViewModel = songLibraryViewModel
        self.midiSettingsViewModel = midiSettingsViewModel
        self.diagnosticsViewModel = diagnosticsViewModel
        self.practiceViewModel = practiceViewModel
    }

    static func make() -> Self {
        let diagnosticsStore = FileDiagnosticsStore()
        let diagnosticsReporter: any DiagnosticsReporting = AppDiagnosticsReporter(
            exportStore: diagnosticsStore
        )
        let diagnosticsExporter: any DiagnosticsArchiveExporting = DiagnosticsArchiveExporter(
            store: diagnosticsStore
        )
        let diagnosticsViewModel = DiagnosticsViewModel(
            store: diagnosticsStore,
            exporter: diagnosticsExporter
        )
        let bundledProvider: any BundledSongLibraryProviderProtocol = EmptyMacBundledSongLibraryProvider()
        let indexStore = SongLibraryIndexStore()
        let fileStore = SongFileStore()
        let audioImportService: any AudioImportServiceProtocol = AudioImportService()
        let songAudioPlayer: SongAudioPlayerProtocol = SongAudioPlayer()
        let importTransactionService = SongLibraryImportTransactionService(
            indexStore: indexStore,
            diagnostics: diagnosticsReporter
        )
        let progressRepository = FilePracticeProgressRepository()
        let outputService = CoreMIDIOutputService(diagnosticsReporter: diagnosticsReporter)
        let practiceSettingsProvider: any PracticeSessionSettingsProviderProtocol = UserDefaultsPracticeSessionSettingsProvider()
        let practiceRoundDefaultsStore: any PracticeRoundDefaultsStoreProtocol = UserDefaultsPracticeRoundDefaultsStore()
        let preparationService: any PracticePreparationServiceProtocol = PracticePreparationService(
            diagnosticsReporter: diagnosticsReporter
        )
        let sessionRecorder = PracticeSessionRecorder(
            repository: progressRepository,
            diagnosticsReporter: diagnosticsReporter,
            performanceAnalyzer: PracticePerformanceAnalyzer(diagnosticsReporter: diagnosticsReporter)
        )
        let takeLibraryViewModel = TakeLibraryViewModel()
        let takePlaybackViewModel = TakePlaybackViewModel()
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
                fileStore: fileStore,
                audioImportService: audioImportService,
                bundledProvider: bundledProvider,
                audioPlayer: songAudioPlayer,
                progressRepository: progressRepository,
                diagnosticsReporter: diagnosticsReporter
            ),
            midiSettingsViewModel: midiSettingsViewModel,
            diagnosticsViewModel: diagnosticsViewModel,
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
                settingsProvider: practiceSettingsProvider,
                roundDefaultsStore: practiceRoundDefaultsStore,
                takeLibraryViewModel: takeLibraryViewModel,
                takePlaybackViewModel: takePlaybackViewModel,
                diagnosticsReporter: diagnosticsReporter
            )
        )
    }
}

private struct EmptyMacBundledSongLibraryProvider: BundledSongLibraryProviderProtocol {
    func bundledEntries() -> [SongLibraryEntry] { [] }
    func musicXMLURL(fileName _: String) -> URL? { nil }
    func audioURL(fileName _: String) -> URL? { nil }
}
