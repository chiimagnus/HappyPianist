import Diagnostics
import Foundation
import Library
import MIDI
import Practice
@testable import HappyPianistMac
import Testing

@MainActor
struct MacPracticeViewModelTests {
    @Test func midiPracticeRecordsOnlyMeasureFactsAndReloadsProgress() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)

        #expect(fixture.viewModel.state == .guiding)
        fixture.input.yield(note: 61)
        await Task.yield()
        #expect(fixture.viewModel.lastAttempt == .wrongNote)

        fixture.input.yield(note: 60)
        await Task.yield()
        #expect(fixture.viewModel.state == .completed)

        let identity = try #require(fixture.viewModel.preparedPractice?.identity)
        #expect(await fixture.viewModel.returnToLibrary())
        let progress = await fixture.progressRepository.progress(for: identity)
        #expect(progress?.measureFacts.isEmpty == false)
    }

    @Test func selectedInputLossStopsGuidingWithoutFallback() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        #expect(fixture.viewModel.state == .guiding)

        fixture.input.emit(.selectedEndpointUnavailable(7))
        await Task.yield()
        await Task.yield()

        #expect(fixture.viewModel.state == .inputUnavailable)
        #expect(fixture.settingsViewModel.selectedInputEndpointID == 7)
        #expect(fixture.input.stopCount > 0)
    }
}

@MainActor
private final class MacPracticeFixture {
    let temporaryRoot: URL
    let songID = UUID()
    let input = PracticeFakeInput()
    let settingsViewModel: MIDISettingsViewModel
    let progressRepository: FilePracticeProgressRepository
    let viewModel: MacPracticeViewModel

    init() throws {
        temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let scoreURL = temporaryRoot.appending(path: "fixture.musicxml")
        try Data(Self.score.utf8).write(to: scoreURL)
        let entry = SongLibraryEntry(
            id: songID,
            displayName: "Fixture",
            musicXMLFileName: "fixture.musicxml",
            scoreFileVersionID: UUID(),
            importedAt: .now,
            audioFileName: nil
        )
        progressRepository = FilePracticeProgressRepository(
            paths: PracticeProgressPaths(rootDirectoryURL: temporaryRoot.appending(path: "progress", directoryHint: .isDirectory))
        )
        let settingsStore = PracticeFakeSettingsStore()
        settingsViewModel = MIDISettingsViewModel(
            settingsStore: settingsStore,
            inputEndpointDiscovery: { [MIDIInputEndpoint(id: 7, name: "Fixture Keyboard")] },
            outputEndpointDiscovery: { [] },
            makeInputService: { [input] _ in input },
            outputService: CoreMIDIOutputService()
        )
        settingsViewModel.selectInput(endpointUniqueID: 7)
        let recorder = PracticeSessionRecorder(
            repository: progressRepository,
            performanceAnalyzer: PracticePerformanceAnalyzer()
        )
        viewModel = MacPracticeViewModel(
            resolveEntry: { requestedID in
                requestedID == entry.id
                    ? .success(ResolvedSongLibraryEntry(entry: entry, scoreURL: scoreURL, diagnosticFileReference: nil))
                    : .failure(SongLibraryEntryResolutionError(
                        preparationError: .scoreFileNotFound,
                        diagnosticFileReference: nil
                    ))
            },
            preparationService: PracticePreparationService(diagnosticsReporter: PracticeNoopDiagnosticsReporter()),
            progressRepository: progressRepository,
            progressRecovery: progressRepository,
            sessionRecorder: recorder,
            midiSettingsViewModel: settingsViewModel
        )
    }

    func removeTemporaryRoot() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    private static let score = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note></measure></part>
    </score-partwise>
    """
}

@MainActor
private final class PracticeFakeSettingsStore: MIDIEndpointSettingsStoring {
    private var settings = MIDIEndpointSettings()

    func load() -> MIDIEndpointSettings { settings }
    func save(_ settings: MIDIEndpointSettings) { self.settings = settings }
}

@MainActor
private final class PracticeFakeInput: MacSelectedMIDIInputControlling {
    var onSourceAvailabilityChange: (@Sendable (MIDIInputSourceAvailability) -> Void)?
    private var midi1Continuation: AsyncStream<MIDI1InputEvent>.Continuation?
    private var midi2Continuation: AsyncStream<MIDI2InputEvent>.Continuation?
    private(set) var stopCount = 0

    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        AsyncStream { midi1Continuation = $0 }
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        AsyncStream { midi2Continuation = $0 }
    }

    func start() throws {}

    func stop() {
        stopCount += 1
        midi1Continuation?.finish()
        midi2Continuation?.finish()
    }

    func yield(note: Int) {
        midi1Continuation?.yield(MIDI1InputEvent(
            kind: .noteOn(note: note, velocity: 96),
            channel: 1,
            group: 0,
            source: MIDIInputSource(identifier: .endpointUniqueID(7), endpointName: nil),
            receivedAt: .now,
            receivedAtUptimeSeconds: ProcessInfo.processInfo.systemUptime + 1
        ))
    }

    func emit(_ availability: MIDIInputSourceAvailability) {
        onSourceAvailabilityChange?(availability)
    }
}

private struct PracticeNoopDiagnosticsReporter: DiagnosticsReporting {
    func recordSystem(_: DiagnosticEvent) {}

    func record(_: DiagnosticEvent) async -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}
