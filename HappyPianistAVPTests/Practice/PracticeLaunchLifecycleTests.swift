import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func duplicatePracticeDisappearAndReturnIntentsRunOneOrderedTeardown() async {
    let coordinator = PracticeWindowReturnCoordinator()
    var calls: [String] = []
    let operationID = UUID()

    for _ in 0..<2 {
        coordinator.begin(
            beginReturn: {
                calls.append("begin")
                return operationID
            },
            leave: { calls.append("leave") },
            closeImmersive: { calls.append("close") },
            recoverImmersive: { calls.append("recover") },
            finishReturn: { receivedID in
                #expect(receivedID == operationID)
                calls.append("finish")
            },
            navigate: { calls.append("navigate") }
        )
    }
    await coordinator.waitForCompletion()

    #expect(calls == ["begin", "leave", "close", "recover", "finish", "navigate"])
}

@MainActor
@Test
func stalePreparedPracticeApplyCannotOverwriteNewerLaunch() async throws {
    let firstID = UUID()
    let secondID = UUID()
    let repository = LaunchRaceProgressRepository(
        delays: [firstID: .milliseconds(80), secondID: .milliseconds(5)]
    )
    let session = PracticeSessionViewModel(
        pressDetectionService: LaunchLifecyclePressDetectionService(),
        chordAttemptAccumulator: LaunchLifecycleChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(repository: repository)
    )
    let appState = AppState()
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: LaunchRaceSessionProvider(session: session).callAsFunction
    )
    var currentID = firstID
    let first = makeLaunchRacePreparedPractice(songID: firstID)
    let second = makeLaunchRacePreparedPractice(songID: secondID)

    let firstTask = Task { @MainActor in
        await guide.applyPreparedPracticeForLaunch(first, isCurrent: { currentID == firstID })
    }
    try await Task.sleep(for: .milliseconds(10))
    currentID = secondID
    let secondTask = Task { @MainActor in
        await guide.applyPreparedPracticeForLaunch(second, isCurrent: { currentID == secondID })
    }

    let firstOutcome = await firstTask.value
    let secondOutcome = await secondTask.value

    #expect(firstOutcome == nil)
    #expect(secondOutcome == .applied)
    #expect(session.songIdentity == second.identity)
    #expect(guide.latestPreparedPractice?.identity == second.identity)
}

@MainActor
@Test
func freshPracticeLaunchUsesFullScoreDefaults() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeLaunchLifecycleSpans()
    let session = makeLaunchLifecycleSession(repository: LaunchLifecycleRepository(progresses: []))

    installLaunchLifecycleScore(in: session, identity: identity, spans: spans)
    await session.restoreProgressIfAvailable()

    let configuration = try #require(session.activeRoundConfiguration)
    #expect(configuration.passage.start == spans.first?.occurrenceID)
    #expect(configuration.passage.end == spans.last?.occurrenceID)
    #expect(configuration.handMode == .both)
    #expect(configuration.tempoScale == 1)
    #expect(configuration.loopEnabled == false)
    #expect(configuration.requiredSuccesses == 3)
    #expect(session.currentStepIndex == session.activeRange?.firstStepIndex)
    #expect(session.lastProgressRestoreOutcome == .none)
}

@MainActor
@Test
func exactPracticeLaunchConfigurationAndResumeAreRestored() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeLaunchLifecycleSpans()
    let passage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))
    let savedConfiguration = PracticeRoundConfiguration(
        passage: passage,
        handMode: .left,
        tempoScale: 0.75,
        loopEnabled: true,
        requiredSuccesses: 4
    )
    let progress = SongPracticeProgress(
        identity: identity,
        activeConfiguration: savedConfiguration,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[2].occurrenceID,
            stepIndex: 2,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let session = makeLaunchLifecycleSession(
        repository: LaunchLifecycleRepository(progresses: [progress])
    )

    installLaunchLifecycleScore(in: session, identity: identity, spans: spans)
    await session.restoreProgressIfAvailable()

    #expect(session.activeRoundConfiguration == savedConfiguration)
    #expect(session.roundConfigurationController.pendingConfiguration == savedConfiguration)
    #expect(session.currentStepIndex == 2)
    #expect(session.isRestoredSessionPaused)
    #expect(session.lastProgressRestoreOutcome == .restored)
}

@MainActor
@Test
func practiceLaunchRevisionMismatchUsesFreshDefaults() async throws {
    let songID = UUID()
    let oldIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "r1")
    let currentIdentity = PracticeSongIdentity(songID: songID, scoreRevision: "r2")
    let spans = makeLaunchLifecycleSpans()
    let oldPassage = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[1].occurrenceID))
    let oldProgress = SongPracticeProgress(
        identity: oldIdentity,
        activeConfiguration: PracticeRoundConfiguration(
            passage: oldPassage,
            handMode: .right,
            tempoScale: 0.6,
            loopEnabled: true,
            requiredSuccesses: 5
        ),
        updatedAt: .now
    )
    let session = makeLaunchLifecycleSession(
        repository: LaunchLifecycleRepository(progresses: [oldProgress])
    )

    installLaunchLifecycleScore(in: session, identity: currentIdentity, spans: spans)
    await session.restoreProgressIfAvailable()

    let configuration = try #require(session.activeRoundConfiguration)
    #expect(configuration.passage.start == spans.first?.occurrenceID)
    #expect(configuration.passage.end == spans.last?.occurrenceID)
    #expect(configuration.handMode == .both)
    #expect(configuration.tempoScale == 1)
    #expect(configuration.loopEnabled == false)
    #expect(session.sessionProgress == nil)
    #expect(session.currentStepIndex == 0)
}

@MainActor
@Test
func practiceLaunchAtoBtoARestoresPersistedStateAndDiscardsDrafts() async throws {
    let identityA = PracticeSongIdentity(songID: UUID(), scoreRevision: "a1")
    let identityB = PracticeSongIdentity(songID: UUID(), scoreRevision: "b1")
    let spans = makeLaunchLifecycleSpans()
    let savedPassageA = try #require(PracticePassage(start: spans[1].occurrenceID, end: spans[2].occurrenceID))
    let savedConfigurationA = PracticeRoundConfiguration(
        passage: savedPassageA,
        handMode: .left,
        tempoScale: 0.8,
        loopEnabled: true,
        requiredSuccesses: 4
    )
    let progressA = SongPracticeProgress(
        identity: identityA,
        activeConfiguration: savedConfigurationA,
        resumePoint: PracticeResumePoint(
            occurrenceID: spans[1].occurrenceID,
            stepIndex: 1,
            updatedAt: .now
        ),
        updatedAt: .now
    )
    let session = makeLaunchLifecycleSession(
        repository: LaunchLifecycleRepository(progresses: [progressA])
    )

    installLaunchLifecycleScore(in: session, identity: identityA, spans: spans)
    await session.restoreProgressIfAvailable()
    session.roundConfigurationController.pendingHandMode = .right
    session.roundConfigurationController.pendingTempoScale = 0.5

    installLaunchLifecycleScore(in: session, identity: identityB, spans: spans)
    await session.restoreProgressIfAvailable()
    #expect(session.roundConfigurationController.pendingHandMode == .both)
    #expect(session.roundConfigurationController.pendingTempoScale == 1)
    session.roundConfigurationController.pendingTempoScale = 0.65

    installLaunchLifecycleScore(in: session, identity: identityA, spans: spans)
    await session.restoreProgressIfAvailable()

    #expect(session.activeRoundConfiguration == savedConfigurationA)
    #expect(session.roundConfigurationController.pendingConfiguration == savedConfigurationA)
    #expect(session.currentStepIndex == 1)
}

@MainActor
private func makeLaunchLifecycleSession(
    repository: LaunchLifecycleRepository
) -> PracticeSessionViewModel {
    PracticeSessionViewModel(
        pressDetectionService: LaunchLifecyclePressDetectionService(),
        chordAttemptAccumulator: LaunchLifecycleChordAccumulator(),
        sleeper: TaskSleeper(),
        progressCoordinator: PracticeProgressCoordinator(
            repository: repository,
            checkpointDelay: .seconds(60)
        )
    )
}

@MainActor
private func installLaunchLifecycleScore(
    in session: PracticeSessionViewModel,
    identity: PracticeSongIdentity,
    spans: [MusicXMLMeasureSpan]
) {
    session.installPreparedSteps(
        [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
            PracticeStep(tick: 480, notes: [PracticeStepNote(midiNote: 62, staff: 1)]),
            PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 64, staff: 1)]),
        ],
        identity: identity,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        measureSpans: spans
    )
}

private func makeLaunchLifecycleSpans() -> [MusicXMLMeasureSpan] {
    [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 0, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 1, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 3, sourceMeasureIndex: 2, sourceMeasureNumberToken: "3", occurrenceIndex: 2, startTick: 960, endTick: 1_440),
    ]
}

private actor LaunchLifecycleRepository: PracticeProgressRepositoryProtocol {
    private var progresses: [PracticeSongIdentity: SongPracticeProgress]

    init(progresses: [SongPracticeProgress]) {
        self.progresses = Dictionary(uniqueKeysWithValues: progresses.map { ($0.identity, $0) })
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: Array(progresses.values)))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        progresses[identity]
    }

    func upsert(_ progress: SongPracticeProgress) {
        progresses[progress.identity] = progress
    }

    func remove(songID: UUID) {
        progresses = progresses.filter { $0.key.songID != songID }
    }
}

private actor LaunchRaceProgressRepository: PracticeProgressRepositoryProtocol {
    let delays: [UUID: Duration]

    init(delays: [UUID: Duration]) {
        self.delays = delays
    }

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }

    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress? {
        if let delay = delays[identity.songID] {
            try? await Task.sleep(for: delay)
        }
        return nil
    }

    func upsert(_: SongPracticeProgress) {}
    func remove(songID _: UUID) {}
}

@MainActor
private final class LaunchRaceSessionProvider: @unchecked Sendable {
    let session: PracticeSessionViewModel

    init(session: PracticeSessionViewModel) {
        self.session = session
    }

    func callAsFunction(_: String?) -> PracticeSessionViewModel { session }
}

private func makeLaunchRacePreparedPractice(songID: UUID) -> PreparedPractice {
    PreparedPractice(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        file: ImportedMusicXMLFile(
            fileName: songID.uuidString,
            storedURL: URL(fileURLWithPath: "/dev/null"),
            importedAt: .now
        ),
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        highlightGuides: [],
        measureSpans: [
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 0,
                startTick: 0,
                endTick: 480
            ),
        ],
        unsupportedNoteCount: 0
    )
}

private struct LaunchLifecyclePressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: FingerTipsSnapshot,
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> { [] }
}

private final class LaunchLifecycleChordAccumulator: ChordAttemptAccumulatorProtocol {
    func register(
        pressedNotes _: Set<Int>,
        expectedNotes _: [Int],
        tolerance _: Int,
        at _: Date
    ) -> StepAttemptMatchResult { .insufficientEvidence }

    func reset() {}
}
