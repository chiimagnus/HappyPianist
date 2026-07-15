import Foundation
import Synchronization
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
            leave: {
                calls.append("leave")
                return .saved
            },
            closeImmersive: { calls.append("close") },
            recoverImmersive: { calls.append("recover") },
            abortReturn: { _ in calls.append("abort") },
            finishReturn: { receivedID in
                #expect(receivedID == operationID)
                calls.append("finish")
                return .saved
            },
            navigate: { calls.append("navigate") }
        )
    }
    await coordinator.waitForCompletion()

    #expect(calls == ["begin", "leave", "close", "recover", "finish", "navigate"])
}

@MainActor
@Test
func failedProgressSaveAbortsReturnWithoutClosingOrNavigatingAndAllowsRetry() async {
    let coordinator = PracticeWindowReturnCoordinator()
    var calls: [String] = []
    var shouldFail = true

    func begin() {
        coordinator.begin(
            beginReturn: {
                calls.append("begin")
                return UUID()
            },
            leave: {
                calls.append("leave")
                if shouldFail { return .failed(message: "disk full") }
                return .saved
            },
            closeImmersive: { calls.append("close") },
            recoverImmersive: { calls.append("recover") },
            abortReturn: { _ in calls.append("abort") },
            finishReturn: { _ in
                calls.append("finish")
                return .saved
            },
            onFailure: { calls.append("failure") },
            navigate: { calls.append("navigate") }
        )
    }

    begin()
    await coordinator.waitForCompletion()
    #expect(calls == ["begin", "leave", "abort", "failure"])
    #expect(coordinator.isReturning == false)

    shouldFail = false
    begin()
    await coordinator.waitForCompletion()
    #expect(calls == [
        "begin", "leave", "abort", "failure",
        "begin", "leave", "close", "recover", "finish", "navigate",
    ])
}

@MainActor
@Test
func systemDisappearRunsBestEffortCloseOnceWithoutReturnNavigation() async {
    let coordinator = PracticeSystemCloseCoordinator()
    var calls: [String] = []

    for _ in 0 ..< 2 {
        coordinator.begin {
            calls.append("finalize")
        }
    }
    await coordinator.waitForCompletion()

    #expect(calls == ["finalize"])
}

@MainActor
@Test
func overlappingReadyPresentationCloseIntentsDismissImmersiveOnce() async {
    let coordinator = PracticeImmersiveCloseCoordinator()
    let gate = MainActorTestGate()
    var closeCount = 0
    var recoverCount = 0
    let first = Task { @MainActor in
        await coordinator.closeIfNeeded(
            isClosed: false,
            close: {
                closeCount += 1
                await gate.wait()
            },
            recover: { recoverCount += 1 }
        )
    }
    await gate.waitUntilEntered()
    let second = Task { @MainActor in
        await coordinator.closeIfNeeded(
            isClosed: false,
            close: { closeCount += 1 },
            recover: { recoverCount += 1 }
        )
    }
    gate.resume()
    await first.value
    await second.value

    #expect(closeCount == 1)
    #expect(recoverCount == 1)
}

@MainActor
@Test
func activeSceneOperationWaitsForCancelledSuspendToFinish() async {
    let coordinator = PracticeSceneLifecycleCoordinator()
    let gate = MainActorTestGate()
    var calls: [String] = []
    coordinator.schedule {
        calls.append("suspend-start")
        await gate.wait()
        calls.append("suspend-finish")
    }
    await gate.waitUntilEntered()

    coordinator.schedule {
        calls.append("activate")
    }
    await Task.yield()
    #expect(calls == ["suspend-start"])

    gate.resume()
    await coordinator.waitForCurrentOperation()
    #expect(calls == ["suspend-start", "suspend-finish", "activate"])
}

@MainActor
private final class MainActorTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false

    func wait() async {
        hasEntered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilEntered() async {
        while hasEntered == false { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
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
        await guide.applyPreparedPracticeForLaunch(
            first,
            restorePolicy: .historicalPreferences(PracticeHistoricalPreferences(
                handMode: .left,
                tempoScale: 0.5,
                loopEnabled: true,
                requiredSuccesses: 5
            )),
            isCurrent: { currentID == firstID }
        )
    }
    try await Task.sleep(for: .milliseconds(10))
    currentID = secondID
    let secondTask = Task { @MainActor in
        await guide.applyPreparedPracticeForLaunch(
            second,
            restorePolicy: .freshDefaults,
            isCurrent: { currentID == secondID }
        )
    }

    let firstOutcome = await firstTask.value
    let secondOutcome = await secondTask.value

    #expect(firstOutcome == nil)
    #expect(secondOutcome == .applied)
    #expect(session.songIdentity == second.identity)
    #expect(session.activeRoundConfiguration?.handMode == .both)
    #expect(session.activeRoundConfiguration?.tempoScale == 1)
    #expect(session.activeRoundConfiguration?.loopEnabled == false)
    #expect(guide.latestPreparedPractice?.identity == second.identity)
}

@MainActor
@Test
func practiceSessionReplacementKeepsWindowRecorderAndDoesNotSplitSession() async throws {
    let repository = LaunchLifecycleSessionRepository()
    let recorder = PracticeSessionRecorder(repository: repository)
    let provider = LaunchLifecycleRecorderSessionProvider(recorder: recorder)
    let appState = AppState()
    let guide = ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: provider.callAsFunction
    )
    let firstSession = guide.practiceSessionViewModel
    let visitID = UUID()
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "revision")
    await recorder.beginVisit(id: visitID, songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)
    await recorder.setGuiding(true)

    #expect(await guide.replacePracticeSessionViewModel() == .replaced)
    #expect(guide.practiceSessionViewModel !== firstSession)
    #expect(guide.practiceSessionViewModel.sessionRecorder === recorder)
    await recorder.checkpoint()
    await recorder.finalize()

    let records = await repository.records()
    #expect(Set(records.map(\.id)) == Set([visitID]))
    #expect(records.dropLast().allSatisfy { $0.termination == .open })
    #expect(records.last?.termination == .normal)
}

@MainActor
@Test
func failedGuidingStartLeavesWindowWithoutSessionFact() async throws {
    let repository = LaunchLifecycleSessionRepository()
    let clock = try LaunchLifecycleRecorderClock()
    let recorder = PracticeSessionRecorder(repository: repository, clock: clock.makeClock())
    let session = LaunchLifecycleRecorderSessionProvider(recorder: recorder).callAsFunction(nil)
    let visitID = UUID()
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "revision")
    await recorder.beginVisit(id: visitID, songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)

    session.startGuidingIfReady()
    await session.waitForSessionRecorderEvents()

    #expect(session.state == .idle)
    #expect(await recorder.finalize() == .idle)
    #expect(await repository.records().isEmpty)
}

@MainActor
@Test
func multipleRoundsAndSettingsUseOneWindowSessionAndPauseActiveTime() async throws {
    let repository = LaunchLifecycleSessionRepository()
    let clock = try LaunchLifecycleRecorderClock()
    let recorder = PracticeSessionRecorder(repository: repository, clock: clock.makeClock())
    let session = LaunchLifecycleRecorderSessionProvider(recorder: recorder).callAsFunction(nil)
    session.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    let identity = try #require(session.songIdentity)
    let visitID = UUID()
    await recorder.beginVisit(id: visitID, songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)

    clock.advance(milliseconds: 5_000)
    session.startGuidingIfReady()
    await session.waitForSessionRecorderEvents()
    clock.advance(milliseconds: 4_000)
    session.setPracticeSettingsPresented(true)
    await session.waitForSessionRecorderEvents()
    clock.advance(milliseconds: 3_000)
    session.setPracticeSettingsPresented(false)
    await session.waitForSessionRecorderEvents()
    clock.advance(milliseconds: 2_000)
    session.skip()
    await session.waitForSessionRecorderEvents()
    #expect(session.state == .completed)

    #expect(session.perform(.continuePassage))
    await session.waitForSessionRecorderEvents()
    clock.advance(milliseconds: 3_000)
    session.skip()
    await session.waitForSessionRecorderEvents()
    clock.advance(milliseconds: 5_000)
    #expect(await recorder.finalize() == .saved)

    let records = await repository.records()
    let final = try #require(records.last)
    #expect(Set(records.map(\.id)) == [visitID])
    #expect(final.practiceWindowDurationMilliseconds == 22_000)
    #expect(final.activePracticeDurationMilliseconds == 9_000)
    #expect(final.termination == .normal)
}

@MainActor
@Test
func inactiveSceneExcludesBackgroundTimeAndRequiresRealGuidingResume() async throws {
    let repository = LaunchLifecycleSessionRepository()
    let clock = try LaunchLifecycleRecorderClock()
    let recorder = PracticeSessionRecorder(repository: repository, clock: clock.makeClock())
    let session = LaunchLifecycleRecorderSessionProvider(recorder: recorder).callAsFunction(nil)
    session.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
        tempoMap: MusicXMLTempoMap(tempoEvents: [])
    )
    let identity = try #require(session.songIdentity)
    let visitID = UUID()
    await recorder.beginVisit(id: visitID, songID: identity.songID, sceneIsActive: true)
    await recorder.bindIdentity(identity)
    session.startGuidingIfReady()
    await session.waitForSessionRecorderEvents()

    clock.advance(milliseconds: 4_000)
    await recorder.setSceneActive(false)
    await session.suspendAndFlushProgress()
    clock.advance(milliseconds: 100_000)
    await recorder.setSceneActive(true)
    session.resumeAfterSuspension()
    session.startGuidingIfReady()
    await session.waitForSessionRecorderEvents()
    clock.advance(milliseconds: 3_000)
    await recorder.finalize()

    let final = try #require(await repository.records().last)
    #expect(final.id == visitID)
    #expect(final.practiceWindowDurationMilliseconds == 7_000)
    #expect(final.activePracticeDurationMilliseconds == 7_000)
}

@MainActor
@Test
func freshPracticeLaunchUsesFullScoreDefaults() async throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "r1")
    let spans = makeLaunchLifecycleSpans()
    let session = makeLaunchLifecycleSession(repository: LaunchLifecycleRepository(progresses: []))

    installLaunchLifecycleScore(in: session, identity: identity, spans: spans)
    await session.applyLaunchRestorePolicy(.freshDefaults)

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
    await session.applyLaunchRestorePolicy(.exactAvailable)

    #expect(session.activeRoundConfiguration == savedConfiguration)
    #expect(session.roundConfigurationController.pendingConfiguration == savedConfiguration)
    #expect(session.currentStepIndex == 2)
    #expect(session.isRestoredSessionPaused)
    #expect(session.lastProgressRestoreOutcome == .restored)
}

@MainActor
@Test
func practiceLaunchRevisionMismatchAppliesOnlyHistoricalPreferencesToFullScore() async throws {
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
    await session.applyLaunchRestorePolicy(.historicalPreferences(
        PracticeHistoricalPreferences(
            handMode: .right,
            tempoScale: 0.6,
            loopEnabled: true,
            requiredSuccesses: 5
        )
    ))

    let configuration = try #require(session.activeRoundConfiguration)
    #expect(configuration.passage.start == spans.first?.occurrenceID)
    #expect(configuration.passage.end == spans.last?.occurrenceID)
    #expect(configuration.handMode == .right)
    #expect(configuration.tempoScale == 0.6)
    #expect(configuration.loopEnabled)
    #expect(configuration.requiredSuccesses == 5)
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
    await session.applyLaunchRestorePolicy(.exactAvailable)
    session.roundConfigurationController.pendingHandMode = .right
    session.roundConfigurationController.pendingTempoScale = 0.5

    installLaunchLifecycleScore(in: session, identity: identityB, spans: spans)
    await session.applyLaunchRestorePolicy(.freshDefaults)
    #expect(session.roundConfigurationController.pendingHandMode == .both)
    #expect(session.roundConfigurationController.pendingTempoScale == 1)
    session.roundConfigurationController.pendingTempoScale = 0.65

    installLaunchLifecycleScore(in: session, identity: identityA, spans: spans)
    await session.applyLaunchRestorePolicy(.exactAvailable)

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

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: progresses.values.filter { $0.identity.songID == songID },
            scoreMetadata: []
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        progresses[progress.identity] = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}

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

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: []))
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
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

private actor LaunchLifecycleSessionRepository: PracticeSessionRepositoryProtocol {
    private var storedRecords: [PracticeSessionRecord] = []

    func upsert(_ session: PracticeSessionRecord) {
        storedRecords.append(session)
    }

    func abandonLiveSession(id _: UUID) {}

    func records() -> [PracticeSessionRecord] {
        storedRecords
    }
}

private final class LaunchLifecycleRecorderClock: Sendable {
    private struct State {
        var monotonicMilliseconds: Int64 = 0
        var wallDate = Date(timeIntervalSince1970: 1_000)
    }

    private let state = Mutex(State())
    let practiceDay: PracticeLocalDay

    init() throws {
        practiceDay = try #require(PracticeLocalDay(
            year: 2026,
            month: 7,
            day: 15,
            timeZoneIdentifier: "Asia/Singapore"
        ))
    }

    func makeClock() -> PracticeSessionRecorderClock {
        PracticeSessionRecorderClock(
            monotonicMilliseconds: { [self] in
                state.withLock(\.monotonicMilliseconds)
            },
            wallDate: { [self] in
                state.withLock(\.wallDate)
            },
            localDay: { [practiceDay] _ in practiceDay }
        )
    }

    func advance(milliseconds: Int64) {
        state.withLock { state in
            state.monotonicMilliseconds += milliseconds
            state.wallDate.addTimeInterval(Double(milliseconds) / 1_000)
        }
    }
}

@MainActor
private final class LaunchLifecycleRecorderSessionProvider: @unchecked Sendable {
    private let recorder: PracticeSessionRecorder

    init(recorder: PracticeSessionRecorder) {
        self.recorder = recorder
    }

    func callAsFunction(_: String?) -> PracticeSessionViewModel {
        PracticeSessionViewModel(
            pressDetectionService: LaunchLifecyclePressDetectionService(),
            chordAttemptAccumulator: LaunchLifecycleChordAccumulator(),
            sleeper: TaskSleeper(),
            sessionRecorder: recorder
        )
    }
}
