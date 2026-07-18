import Foundation
@testable import HappyPianistAVP
import Testing

@Test
@MainActor
func clearingPreparedPracticePreventsSessionReplacementFromResurrectingSong() async {
    let appState = AppState()
    appState.practiceSetupState.selectedPianoModeID = "kept-mode"
    let guide = makeLifecycleGuide(appState: appState)
    let prepared = makeLifecyclePreparedPractice()
    let calibration = PianoCalibration(
        a0: .zero,
        c8: SIMD3<Float>(1, 0, 0),
        planeHeight: 0
    )
    guide.practiceSessionViewModel.calibration = calibration

    #expect(await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .freshDefaults,
        isCurrent: { true }
    ) == .applied)
    #expect(guide.practiceSessionViewModel.songIdentity == prepared.identity)
    #expect(guide.practiceSessionViewModel.performancePlan == prepared.performancePlan)
    #expect(guide.practiceSessionViewModel.notationProjection == prepared.notationProjection)
    #expect(guide.latestPreparedPractice?.identity == prepared.identity)
    #expect(guide.latestPreparedPractice?.scoreContext == prepared.scoreContext)

    await guide.clearPreparedPracticeForLaunch()
    await guide.clearPreparedPracticeForLaunch()

    #expect(guide.practiceSessionViewModel.songIdentity == nil)
    #expect(guide.practiceSessionViewModel.performancePlan == nil)
    #expect(guide.practiceSessionViewModel.notationProjection == nil)
    #expect(guide.practiceSessionViewModel.steps.isEmpty)
    #expect(guide.latestPreparedPractice == nil)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == nil)
    #expect(appState.practiceSetupState.importedSteps.isEmpty)
    #expect(appState.practiceSetupState.selectedPianoModeID == "kept-mode")
    #expect(guide.practiceSessionViewModel.calibration == calibration)

    await guide.replacePracticeSessionViewModel()

    #expect(guide.practiceSessionViewModel.songIdentity == nil)
    #expect(guide.practiceSessionViewModel.steps.isEmpty)
    #expect(guide.latestPreparedPractice == nil)
}

@Test
@MainActor
func replacingPracticeSessionReappliesTheSameHistoricalRestorePolicy() async {
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState)
    let prepared = makeLifecyclePreparedPractice()
    let policy = PracticeLaunchRestorePolicy.historicalPreferences(
        PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.7,
            loopEnabled: true,
            requiredSuccesses: 4
        )
    )
    #expect(await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: policy,
        isCurrent: { true }
    ) == .applied)
    let first = guide.practiceSessionViewModel

    await guide.replacePracticeSessionViewModel()

    let replacement = guide.practiceSessionViewModel
    #expect(replacement !== first)
    #expect(replacement.songIdentity == prepared.identity)
    #expect(replacement.performancePlan == prepared.performancePlan)
    #expect(replacement.notationProjection == prepared.notationProjection)
    #expect(replacement.activeRoundConfiguration?.handMode == .left)
    #expect(replacement.activeRoundConfiguration?.tempoScale == 0.7)
    #expect(replacement.activeRoundConfiguration?.loopEnabled == true)
    #expect(replacement.activeRoundConfiguration?.requiredSuccesses == 4)
    #expect(replacement.activeRoundConfiguration?.passage.start == prepared.measureSpans.first?.occurrenceID)
    #expect(replacement.activeRoundConfiguration?.passage.end == prepared.measureSpans.last?.occurrenceID)
}

@Test
@MainActor
func replacingAfterCurrentRevisionStartsRestoresItsExactProgress() async {
    let repository = LifecycleProgressRepository()
    let coordinator = PracticeProgressCoordinator(
        repository: repository,
        checkpointDelay: .seconds(60)
    )
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState, progressCoordinator: coordinator)
    let prepared = makeLifecyclePreparedPractice()
    #expect(await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .historicalPreferences(PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.7,
            loopEnabled: true,
            requiredSuccesses: 4
        )),
        isCurrent: { true }
    ) == .applied)
    guide.practiceSessionViewModel.startGuidingIfReady()
    #expect(guide.practiceSessionViewModel.sessionProgress != nil)

    await guide.replacePracticeSessionViewModel()

    #expect(guide.practiceSessionViewModel.activeRoundConfiguration?.handMode == .left)
    #expect(guide.practiceSessionViewModel.activeRoundConfiguration?.tempoScale == 0.7)
    #expect(guide.practiceSessionViewModel.lastProgressRestoreOutcome == .restored)
    #expect(guide.practiceSessionViewModel.isRestoredSessionPaused)
    #expect(await repository.progress(for: prepared.identity) != nil)
}

@Test
@MainActor
func replacementStopsAndKeepsOldSessionWhenProgressCannotBeSaved() async {
    let repository = FailingLifecycleProgressRepository()
    let coordinator = PracticeProgressCoordinator(
        repository: repository,
        checkpointDelay: .seconds(60)
    )
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState, progressCoordinator: coordinator)
    let prepared = makeLifecyclePreparedPractice()
    #expect(await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .freshDefaults,
        isCurrent: { true }
    ) == .applied)
    guide.practiceSessionViewModel.startGuidingIfReady()
    let oldSession = guide.practiceSessionViewModel
    let oldProgress = oldSession.sessionProgress

    let result = await guide.replacePracticeSessionViewModel()

    #expect(result == .progressSaveFailed)
    #expect(guide.practiceSessionViewModel === oldSession)
    #expect(oldSession.hasShutdown == false)
    #expect(oldSession.sessionProgress == oldProgress)
    #expect(guide.practiceProgressSaveErrorMessage != nil)
}

@Test
@MainActor
func clearingPreparedPracticePreservesCurrentSessionWhenProgressCannotBeSaved() async {
    let repository = FailingLifecycleProgressRepository()
    let coordinator = PracticeProgressCoordinator(
        repository: repository,
        checkpointDelay: .seconds(60)
    )
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState, progressCoordinator: coordinator)
    let prepared = makeLifecyclePreparedPractice()
    #expect(await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .freshDefaults,
        isCurrent: { true }
    ) == .applied)
    guide.practiceSessionViewModel.startGuidingIfReady()
    let session = guide.practiceSessionViewModel

    let status = await guide.clearPreparedPracticeForLaunch()

    guard case .failed = status else {
        Issue.record("Expected progress-save failure")
        return
    }
    #expect(guide.practiceSessionViewModel === session)
    #expect(session.hasShutdown == false)
    #expect(session.songIdentity == prepared.identity)
    #expect(guide.latestPreparedPractice?.identity == prepared.identity)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == prepared.identity)
    #expect(guide.practiceProgressSaveErrorMessage != nil)
}

@Test
@MainActor
func clearWinsWhilePreparedPracticeAwaitsProgressRestore() async {
    let repository = SuspendedLifecycleProgressRepository()
    let coordinator = PracticeProgressCoordinator(repository: repository)
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState, progressCoordinator: coordinator)
    let prepared = makeLifecyclePreparedPractice()
    let applyTask = Task { @MainActor in
        await guide.applyPreparedPracticeForLaunch(
            prepared,
            restorePolicy: .freshDefaults,
            isCurrent: { true }
        )
    }
    await repository.waitForRequest(identity: prepared.identity)

    await guide.clearPreparedPracticeForLaunch()
    await repository.resume(identity: prepared.identity)
    let applied = await applyTask.value

    #expect(applied == nil)
    #expect(guide.latestPreparedPractice == nil)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == nil)
    #expect(appState.practiceSetupState.importedSteps.isEmpty)
    #expect(guide.practiceSessionViewModel.songIdentity == nil)
    #expect(guide.practiceSessionViewModel.steps.isEmpty)
    #expect(guide.practiceSessionViewModel.activeRoundConfiguration == nil)
    #expect(guide.practiceSessionViewModel.progressGeneration == nil)
    #expect(guide.practiceSessionViewModel.sessionProgress == nil)
}

@Test
@MainActor
func clearingShutdownPracticeSessionInstallsFreshEmptyReplacement() async {
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState)
    let prepared = makeLifecyclePreparedPractice()
    #expect(await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .freshDefaults,
        isCurrent: { true }
    ) == .applied)
    let shutdownSession = guide.practiceSessionViewModel
    await shutdownSession.flushAndShutdown()
    #expect(shutdownSession.hasShutdown)

    await guide.clearPreparedPracticeForLaunch()

    #expect(guide.practiceSessionViewModel !== shutdownSession)
    #expect(guide.practiceSessionViewModel.hasShutdown == false)
    #expect(guide.practiceSessionViewModel.songIdentity == nil)
    #expect(guide.practiceSessionViewModel.steps.isEmpty)
    #expect(guide.latestPreparedPractice == nil)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == nil)
}

@Test
@MainActor
func replacementDuringProgressRestoreInvalidatesOldPreparedApply() async {
    let repository = FirstSuspendedLifecycleProgressRepository()
    let coordinator = PracticeProgressCoordinator(repository: repository)
    let appState = AppState()
    let guide = makeLifecycleGuide(appState: appState, progressCoordinator: coordinator)
    let prepared = makeLifecyclePreparedPractice()
    let oldSession = guide.practiceSessionViewModel
    let applyTask = Task { @MainActor in
        await guide.applyPreparedPracticeForLaunch(
            prepared,
            restorePolicy: .freshDefaults,
            isCurrent: { true }
        )
    }
    await repository.waitForFirstRequest()

    await guide.replacePracticeSessionViewModel()
    let replacementSession = guide.practiceSessionViewModel
    await repository.resumeFirstRequest()
    let staleOutcome = await applyTask.value

    #expect(staleOutcome == nil)
    #expect(replacementSession !== oldSession)
    #expect(replacementSession.songIdentity == nil)
    #expect(guide.latestPreparedPractice == nil)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == nil)

    let replacementOutcome = await guide.applyPreparedPracticeForLaunch(
        prepared,
        restorePolicy: .freshDefaults,
        isCurrent: { true }
    )
    #expect(replacementOutcome == .applied)
    #expect(guide.practiceSessionViewModel === replacementSession)
    #expect(replacementSession.songIdentity == prepared.identity)
    #expect(guide.latestPreparedPractice?.identity == prepared.identity)
    #expect(guide.latestPreparedPractice?.scoreContext == prepared.scoreContext)
}

@Test
@MainActor
func sessionProjectsCurrentGuideActivityOntoAuthoritativeNotation() throws {
    let identity = PracticeSongIdentity(songID: UUID(), scoreRevision: "notation")
    let steps = [
        PracticeStep(
            tick: 0,
            notes: [
                PracticeStepNote(
                    midiNote: 60,
                    staff: 1,
                    handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
                ),
            ]
        ),
    ]
    let plan = makeTestScorePerformancePlan(identity: identity, steps: steps)
    let event = try #require(plan.noteEvents.first)
    let score = MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            sourceID: event.sourceNoteID,
            partID: event.sourceNoteID.partID,
            measureNumber: 1,
            tick: event.writtenOnTick,
            durationTicks: event.writtenOffTick - event.writtenOnTick,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4),
            midiNote: event.midiNote,
            isRest: false,
            isChord: false,
            tieStart: false,
            tieStop: false,
            staff: event.staff,
            voice: event.voice
        ),
    ])
    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        durationTicks: 480,
        practiceStepIndex: 0,
        activeNotes: [],
        triggeredNotes: [
            PianoHighlightNote(
                occurrenceID: event.id.description,
                midiNote: event.midiNote,
                staff: event.staff,
                voice: event.voice,
                velocity: event.velocity,
                onTick: event.performedOnTick,
                offTick: event.performedOffTick,
                fingeringText: nil,
                handAssignment: event.handAssignment
            ),
        ],
        releasedMIDINotes: []
    )
    let session = PracticeSessionViewModel(
        pressDetectionService: PressDetectionService(),
        chordAttemptAccumulator: ChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )
    session.installPreparedSteps(
        steps,
        identity: identity,
        performancePlan: plan,
        notationProjection: ScoreNotationProjection(plan: plan, sourceScore: score),
        highlightGuides: [guide],
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
        ]
    )

    session.startGuidingIfReady()

    #expect(session.activeNotationProjection?.activeState.occurrenceIDs == [event.id])
}

@MainActor
private func makeLifecycleGuide(
    appState: AppState,
    progressCoordinator: PracticeProgressCoordinator? = nil
) -> ARGuideViewModel {
    ARGuideViewModel(
        appState: appState,
        practiceSetupState: appState.practiceSetupState,
        pianoModeRegistry: PianoModeRegistryService(modes: []),
        makePracticeSessionViewModel: { _ in
            PracticeSessionViewModel(
                pressDetectionService: PressDetectionService(),
                chordAttemptAccumulator: ChordAttemptAccumulator(),
                sleeper: TaskSleeper(),
                progressCoordinator: progressCoordinator
            )
        }
    )
}

private func makeLifecyclePreparedPractice() -> PreparedPractice {
    let songID = UUID()
    return makeTestPreparedPractice(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: "revision"),
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)]),
        ],
        file: ImportedMusicXMLFile(
            fileName: "Lifecycle",
            storedURL: URL(fileURLWithPath: "/dev/null"),
            importedAt: .now
        ),
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
        ]
    )
}

private actor SuspendedLifecycleProgressRepository: PracticeProgressRepositoryProtocol {
    private var continuations: [
        PracticeSongIdentity: CheckedContinuation<SongPracticeProgress?, Never>
    ] = [:]

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress? {
        await withCheckedContinuation { continuation in
            continuations[identity] = continuation
        }
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
    }

    func waitForRequest(identity: PracticeSongIdentity) async {
        while continuations[identity] == nil {
            await Task.yield()
        }
    }

    func resume(identity: PracticeSongIdentity) {
        continuations.removeValue(forKey: identity)?.resume(returning: nil)
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor LifecycleProgressRepository: PracticeProgressRepositoryProtocol {
    private var storedProgress: SongPracticeProgress?

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument(songs: storedProgress.map { [$0] } ?? []))
    }

    func progress(for identity: PracticeSongIdentity) -> SongPracticeProgress? {
        storedProgress?.identity == identity ? storedProgress : nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(
            songID: songID,
            progresses: storedProgress.map { $0.identity.songID == songID ? [$0] : [] } ?? [],
            scoreMetadata: [],
            sessions: []
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        storedProgress = progress
    }

    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID: UUID) {
        if storedProgress?.identity.songID == songID { storedProgress = nil }
    }
}

private actor FailingLifecycleProgressRepository: PracticeProgressRepositoryProtocol {
    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
    }

    func upsert(_: SongPracticeProgress) throws {
        throw CocoaError(.fileWriteOutOfSpace)
    }

    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}

private actor FirstSuspendedLifecycleProgressRepository: PracticeProgressRepositoryProtocol {
    private var firstContinuation: CheckedContinuation<SongPracticeProgress?, Never>?
    private var didSuspendFirstRequest = false

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) async -> SongPracticeProgress? {
        guard didSuspendFirstRequest == false else { return nil }
        didSuspendFirstRequest = true
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
    }

    func waitForFirstRequest() async {
        while firstContinuation == nil {
            await Task.yield()
        }
    }

    func resumeFirstRequest() {
        firstContinuation?.resume(returning: nil)
        firstContinuation = nil
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) {}
    func remove(songID _: UUID) {}
}
