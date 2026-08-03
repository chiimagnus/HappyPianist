import Diagnostics
import Foundation
import Library
import MIDI
import MusicXML
import Practice
@testable import HappyPianistMac
import Testing

@MainActor
struct MacPracticeViewModelTests {
    @Test func startsFromThePersistedInputWithoutOpeningSettings() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)

        #expect(fixture.viewModel.state == .guiding)
        #expect(fixture.input.startCount > 0)
    }

    @Test func midiPracticeRecordsOnlyMeasureFactsAndReloadsProgress() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)

        #expect(fixture.viewModel.state == .guiding)
        fixture.input.yield(note: 61)
        #expect(await eventually { fixture.viewModel.lastAttempt == .wrongNote })
        #expect(fixture.viewModel.lastAttempt == .wrongNote)

        fixture.input.yield(note: 60)
        #expect(await eventually { fixture.viewModel.state == .completed })
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
        #expect(await eventually { fixture.viewModel.state == .inputUnavailable })

        #expect(fixture.viewModel.state == .inputUnavailable)
        #expect(fixture.settingsViewModel.selectedInputEndpointID == 7)
        #expect(fixture.input.stopCount > 0)
    }

    @Test func selectedOutputEnablesCurrentStepReferenceAndReturnStopsIt() async throws {
        let fixture = try MacPracticeFixture(hasSelectedOutput: true)
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        #expect(fixture.viewModel.canPlayCurrentStepReference)

        await fixture.viewModel.playCurrentStepReference()

        #expect(fixture.referencePlayback.oneShotCommands.map(\.kind) == [.noteOn(midi: 60, velocity: 96)])
        #expect(await fixture.viewModel.returnToLibrary())
        #expect(fixture.referencePlayback.stopCount == 1)
    }

    @Test func missingOutputHidesCurrentStepReferenceWithoutBlockingMIDIPractice() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)

        #expect(fixture.viewModel.state == .guiding)
        #expect(fixture.viewModel.canPlayCurrentStepReference == false)
    }

    @Test func reloadingPracticePreservesApprovedMeasureFacts() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        fixture.input.yield(note: 60)
        #expect(await eventually { fixture.viewModel.state == .completed })
        let identity = try #require(fixture.viewModel.preparedPractice?.identity)
        #expect(await fixture.viewModel.returnToLibrary())

        await fixture.viewModel.load(songID: fixture.songID)
        fixture.input.yield(note: 61)
        #expect(await eventually { fixture.viewModel.lastAttempt == .wrongNote })
        #expect(await fixture.viewModel.returnToLibrary())

        let progress = await fixture.progressRepository.progress(for: identity)
        let facts = try #require(progress?.measureFacts.first)
        #expect(facts.successfulAttempts == 1)
        #expect(facts.failedAttempts == 1)
    }

    @Test func appliedRoundConfigurationRestartsTheSelectedPassageAndRestoresExactly() async throws {
        let fixture = try MacPracticeFixture(hasSelectedOutput: true, hasTwoMeasures: true)
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        let prepared = try #require(fixture.viewModel.preparedPractice)
        let selectedPassage = try #require(PracticePassage(
            start: prepared.measureSpans[1].occurrenceID,
            end: prepared.measureSpans[1].occurrenceID
        ))
        let expectedConfiguration = PracticeRoundConfiguration(
            passage: selectedPassage,
            handMode: .right,
            tempoScale: 0.75,
            loopEnabled: false,
            requiredSuccesses: 3
        )
        let controller = fixture.viewModel.roundConfigurationController
        controller.pendingPassage = selectedPassage
        controller.pendingHandMode = expectedConfiguration.handMode
        controller.pendingTempoScale = expectedConfiguration.tempoScale
        controller.pendingLoopEnabled = expectedConfiguration.loopEnabled
        controller.pendingRequiredSuccesses = expectedConfiguration.requiredSuccesses

        #expect(await fixture.viewModel.applyPendingRoundConfiguration())
        #expect(fixture.viewModel.currentStepIndex == 1)

        await fixture.viewModel.playCurrentStepReference()
        #expect(fixture.referencePlayback.oneShotCommands.map(\.kind) == [.noteOn(midi: 72, velocity: 96)])

        let identity = prepared.identity
        #expect(await fixture.viewModel.returnToLibrary())
        let saved = try #require(await fixture.progressRepository.progress(for: identity))
        #expect(saved.activeConfiguration == expectedConfiguration)
        #expect(saved.resumePoint == nil)

        await fixture.viewModel.load(songID: fixture.songID)
        #expect(fixture.viewModel.state == .guiding)
        #expect(fixture.viewModel.currentStepIndex == 1)
    }

    @Test func loopedPassageRestartsAndPersistsItsFirstStepAsTheResumePoint() async throws {
        let fixture = try MacPracticeFixture(hasTwoMeasures: true)
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        let prepared = try #require(fixture.viewModel.preparedPractice)
        let fullPassage = try #require(PracticePassage(
            start: prepared.measureSpans[0].occurrenceID,
            end: prepared.measureSpans[1].occurrenceID
        ))
        let controller = fixture.viewModel.roundConfigurationController
        controller.pendingPassage = fullPassage
        controller.pendingHandMode = .both
        controller.pendingLoopEnabled = true
        controller.pendingRequiredSuccesses = 1

        #expect(await fixture.viewModel.applyPendingRoundConfiguration())
        fixture.input.yield(note: 48)
        #expect(await eventually { fixture.viewModel.currentStepIndex == 1 })
        fixture.input.yield(note: 72)
        #expect(await eventually { fixture.viewModel.currentStepIndex == 0 })
        #expect(fixture.viewModel.state == .guiding)

        #expect(await fixture.viewModel.returnToLibrary())
        let progress = try #require(await fixture.progressRepository.progress(for: prepared.identity))
        #expect(progress.resumePoint?.occurrenceID == prepared.measureSpans[0].occurrenceID)
        #expect(progress.resumePoint?.stepIndex == 0)
    }

    @Test func invalidExactRestoreRepairsConfigurationWithoutDiscardingMeasureFacts() async throws {
        let fixture = try MacPracticeFixture(hasTwoMeasures: true)
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        let prepared = try #require(fixture.viewModel.preparedPractice)
        #expect(await fixture.viewModel.returnToLibrary())

        let missingSource = PracticeSourceMeasureID(
            partID: "P1",
            sourceMeasureIndex: 99,
            sourceNumberToken: "100"
        )
        let missingOccurrence = PracticeMeasureOccurrenceID(
            sourceMeasureID: missingSource,
            occurrenceIndex: 99
        )
        let invalidPassage = try #require(PracticePassage(
            start: missingOccurrence,
            end: missingOccurrence
        ))
        let retainedFact = MeasurePracticeFacts(
            sourceMeasureID: prepared.measureSpans[0].occurrenceID.sourceMeasureID,
            handMode: .both,
            state: .learning,
            successfulAttempts: 1
        )
        try await fixture.progressRepository.upsert(SongPracticeProgress(
            identity: prepared.identity,
            activeConfiguration: PracticeRoundConfiguration(
                passage: invalidPassage,
                handMode: .left,
                tempoScale: 0.75,
                loopEnabled: true,
                requiredSuccesses: 3
            ),
            resumePoint: PracticeResumePoint(
                occurrenceID: missingOccurrence,
                stepIndex: 99,
                updatedAt: .now
            ),
            measureFacts: [retainedFact],
            updatedAt: .now
        ))

        await fixture.viewModel.load(songID: fixture.songID)

        let fullPassage = try #require(PracticePassage(
            start: prepared.measureSpans[0].occurrenceID,
            end: prepared.measureSpans[1].occurrenceID
        ))
        let repaired = try #require(await fixture.progressRepository.progress(for: prepared.identity))
        #expect(fixture.viewModel.state == .guiding)
        #expect(fixture.viewModel.currentStepIndex == 0)
        #expect(repaired.activeConfiguration == PracticeRoundConfiguration(
            passage: fullPassage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: 1
        ))
        #expect(repaired.resumePoint == nil)
        #expect(repaired.measureFacts == [retainedFact])
    }
}

@MainActor
private func eventually(
    _ condition: @MainActor () -> Bool
) async -> Bool {
    for _ in 0 ..< 100 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

@MainActor
private final class MacPracticeFixture {
    let temporaryRoot: URL
    let songID = UUID()
    let input = PracticeFakeInput()
    let settingsViewModel: MIDISettingsViewModel
    let progressRepository: FilePracticeProgressRepository
    let viewModel: MacPracticeViewModel
    let referencePlayback = PracticeFakePlaybackService()

    init(hasSelectedOutput: Bool = false, hasTwoMeasures: Bool = false) throws {
        temporaryRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let scoreURL = temporaryRoot.appending(path: "fixture.musicxml")
        try Data((hasTwoMeasures ? Self.twoMeasureScore : Self.score).utf8).write(to: scoreURL)
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
        let settingsStore = PracticeFakeSettingsStore(settings: MIDIEndpointSettings(
            inputEndpointUniqueID: 7,
            outputEndpointUniqueID: hasSelectedOutput ? 9 : nil
        ))
        settingsViewModel = MIDISettingsViewModel(
            settingsStore: settingsStore,
            inputEndpointDiscovery: { [MIDIInputEndpoint(id: 7, name: "Fixture Keyboard")] },
            outputEndpointDiscovery: {
                hasSelectedOutput ? [MIDIDestinationInfo(id: 9, name: "Fixture Synth")] : []
            },
            makeInputService: { [input] _ in input },
            outputService: CoreMIDIOutputService()
        )
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
            midiSettingsViewModel: settingsViewModel,
            makeReferencePlaybackService: { [referencePlayback] _ in referencePlayback },
            settingsProvider: PracticeFakeSessionSettingsProvider(),
            roundDefaultsStore: PracticeFakeRoundDefaultsStore()
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

    private static let twoMeasureScore = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note></measure>
        <measure number="2"><note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note></measure>
      </part>
    </score-partwise>
    """
}

private struct PracticeFakeSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode = .step
    let practiceHandMode: PracticeHandMode = .both
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private final class PracticeFakeRoundDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    let tempoScale = 1.0
    let loopEnabled = false
    let requiredSuccesses = 1

    func save(
        handMode _: PracticeHandMode,
        manualAdvanceMode _: ManualAdvanceMode,
        soundRoutingSettings _: PracticeSoundRoutingSettings,
        tempoScale _: Double,
        loopEnabled _: Bool,
        requiredSuccesses _: Int
    ) {}
}

@MainActor
private final class PracticeFakeSettingsStore: MIDIEndpointSettingsStoring {
    private var settings: MIDIEndpointSettings

    init(settings: MIDIEndpointSettings) {
        self.settings = settings
    }

    func load() -> MIDIEndpointSettings { settings }
    func save(_ settings: MIDIEndpointSettings) { self.settings = settings }
}

@MainActor
private final class PracticeFakeInput: MacSelectedMIDIInputControlling {
    var onSourceAvailabilityChange: (@Sendable (MIDIInputSourceAvailability) -> Void)?
    private var midi1Continuation: AsyncStream<MIDI1InputEvent>.Continuation?
    private var midi2Continuation: AsyncStream<MIDI2InputEvent>.Continuation?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        AsyncStream { midi1Continuation = $0 }
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        AsyncStream { midi2Continuation = $0 }
    }

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
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

@MainActor
private final class PracticeFakePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private(set) var oneShotCommands: [PracticePlaybackCommand] = []
    private(set) var stopCount = 0

    func warmUp() async throws {}
    func load(sequence _: PracticeSequencerSequence) async throws {}
    func play(fromSeconds _: TimeInterval) async throws {}
    func currentSeconds() async -> TimeInterval { 0 }
    func execute(commands _: [PracticePlaybackCommand]) async throws {}
    func stopAllLiveNotes() async {}

    func stop(resetCommands _: [PerformanceTransportCommand]) async {
        stopCount += 1
    }

    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds _: TimeInterval) async throws {
        oneShotCommands = commands
    }
}

private struct PracticeNoopDiagnosticsReporter: DiagnosticsReporting {
    func recordSystem(_: DiagnosticEvent) {}

    func record(_: DiagnosticEvent) async -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}
