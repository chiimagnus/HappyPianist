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

    #expect(await guide.applyPreparedPractice(prepared, isCurrent: { true }))
    #expect(guide.practiceSessionViewModel.songIdentity == prepared.identity)
    #expect(guide.latestPreparedPractice?.identity == prepared.identity)

    await guide.clearPreparedPracticeForLaunch()
    await guide.clearPreparedPracticeForLaunch()

    #expect(guide.practiceSessionViewModel.songIdentity == nil)
    #expect(guide.practiceSessionViewModel.steps.isEmpty)
    #expect(guide.latestPreparedPractice == nil)
    #expect(appState.practiceSetupState.preparedPracticeIdentity == nil)
    #expect(appState.practiceSetupState.importedSteps.isEmpty)
    #expect(appState.practiceSetupState.selectedPianoModeID == "kept-mode")

    await guide.replacePracticeSessionViewModel()

    #expect(guide.practiceSessionViewModel.songIdentity == nil)
    #expect(guide.practiceSessionViewModel.steps.isEmpty)
    #expect(guide.latestPreparedPractice == nil)
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
        await guide.applyPreparedPractice(prepared, isCurrent: { true })
    }
    await repository.waitForRequest(identity: prepared.identity)

    await guide.clearPreparedPracticeForLaunch()
    await repository.resume(identity: prepared.identity)
    let applied = await applyTask.value

    #expect(applied == false)
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
    #expect(await guide.applyPreparedPracticeForLaunch(prepared, isCurrent: { true }) == .applied)
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
        await guide.applyPreparedPracticeForLaunch(prepared, isCurrent: { true })
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
        isCurrent: { true }
    )
    #expect(replacementOutcome == .applied)
    #expect(guide.practiceSessionViewModel === replacementSession)
    #expect(replacementSession.songIdentity == prepared.identity)
    #expect(guide.latestPreparedPractice?.identity == prepared.identity)
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
    return PreparedPractice(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: "revision"),
        steps: [
            PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)]),
        ],
        file: ImportedMusicXMLFile(
            fileName: "Lifecycle",
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

private actor SuspendedLifecycleProgressRepository: PracticeProgressRepositoryProtocol {
    private var continuations: [
        PracticeSongIdentity: CheckedContinuation<SongPracticeProgress?, Never>
    ] = [:]

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }

    func progress(for identity: PracticeSongIdentity) async -> SongPracticeProgress? {
        await withCheckedContinuation { continuation in
            continuations[identity] = continuation
        }
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
    func remove(songID _: UUID) {}
}

private actor FirstSuspendedLifecycleProgressRepository: PracticeProgressRepositoryProtocol {
    private var firstContinuation: CheckedContinuation<SongPracticeProgress?, Never>?
    private var didSuspendFirstRequest = false

    func load() -> PracticeProgressLoadResult { .loaded(PracticeProgressDocument()) }

    func progress(for _: PracticeSongIdentity) async -> SongPracticeProgress? {
        guard didSuspendFirstRequest == false else { return nil }
        didSuspendFirstRequest = true
        return await withCheckedContinuation { continuation in
            firstContinuation = continuation
        }
    }

    func waitForFirstRequest() async {
        while firstContinuation == nil { await Task.yield() }
    }

    func resumeFirstRequest() {
        firstContinuation?.resume(returning: nil)
        firstContinuation = nil
    }

    func upsert(_: SongPracticeProgress) {}
    func remove(songID _: UUID) {}
}
