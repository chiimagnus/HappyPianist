import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func practiceLaunchRegistersWithoutPreparingThenActivatesExactlyOnce() async {
    let fixture = makePracticeLaunchFixture()

    fixture.owner.request(songID: fixture.songA)

    #expect(await fixture.preparation.requestedSongIDs().isEmpty)
    #expect(fixture.applicator.clearCount == 0)
    #expect(fixture.owner.state == .requested(songID: fixture.songA))

    await fixture.owner.activateCurrentRequest()
    await fixture.owner.activateCurrentRequest()

    #expect(await fixture.preparation.requestedSongIDs() == [fixture.songA])
    #expect(fixture.applicator.clearCount == 1)
    #expect(fixture.applicator.appliedSongIDs == [fixture.songA])
    #expect(fixture.applicator.restorePolicies == [.freshDefaults])
    #expect(fixture.owner.state == .ready(PracticeSongIdentity(songID: fixture.songA, scoreRevision: fixture.songA.uuidString)))
    await fixture.metadataRepository.waitForMetadataCount(1)
    let metadata = await fixture.metadataRepository.metadata
    #expect(metadata.first?.scoreFileVersionID == fixture.songA)
    #expect(metadata.first?.totalSourceMeasureCount == 1)
    let resolution = await fixture.reporter.events.first { $0.code == .practiceHistoryResolution }
    #expect(resolution?.reason == "exactMissing:noValidCandidate")
}

@MainActor
@Test
func practiceLaunchKeepsOneVisitIdentityForRetryAndCreatesAnotherForNewRequest() async {
    let fixture = makePracticeLaunchFixture(error: .noPlayableNotes)
    fixture.owner.request(songID: fixture.songA)
    let firstVisitID = fixture.owner.currentVisitID
    await fixture.owner.activateCurrentRequest()

    await fixture.owner.retry()
    #expect(fixture.owner.currentVisitID == firstVisitID)

    fixture.owner.request(songID: fixture.songB)
    #expect(fixture.owner.currentVisitID != firstVisitID)
}

@MainActor
@Test
func successfulLaunchBindsPreparedRevisionToWindowRecorder() async throws {
    let sessionRepository = PracticeLaunchSessionRepository()
    let recorder = PracticeSessionRecorder(repository: sessionRepository)
    let fixture = makePracticeLaunchFixture(sessionRecorder: recorder)
    fixture.owner.request(songID: fixture.songA)
    let visitID = try #require(fixture.owner.currentVisitID)

    await fixture.owner.activateCurrentRequest()
    await recorder.setGuiding(true)
    _ = await recorder.checkpoint()

    let record = try #require(await sessionRepository.records().last)
    #expect(record.id == visitID)
    #expect(record.songID == fixture.songA)
    #expect(record.scoreRevision == fixture.songA.uuidString)
}

@MainActor
@Test
func failedRecorderFinalizeBlocksReturnUntilUserDiscardsPendingDelta() async throws {
    let sessionRepository = PracticeLaunchSessionRepository()
    let recorder = PracticeSessionRecorder(repository: sessionRepository)
    let fixture = makePracticeLaunchFixture(sessionRecorder: recorder)
    fixture.owner.request(songID: fixture.songA)
    let visitID = try #require(fixture.owner.currentVisitID)
    await fixture.owner.activateCurrentRequest()
    await recorder.setGuiding(true)
    _ = await recorder.checkpoint()
    let clearCountBeforeReturn = fixture.applicator.clearCount
    await sessionRepository.failNextWrites(1)

    let failedOperation = fixture.owner.beginReturn()
    let failedStatus = await fixture.owner.finishReturn(operationID: failedOperation)

    guard case .failed = failedStatus else {
        Issue.record("Expected recorder finalization failure")
        return
    }
    #expect(fixture.owner.requestedSongID == fixture.songA)
    #expect(fixture.applicator.clearCount == clearCountBeforeReturn)
    #expect(fixture.applicator.returnCommitCount == 0)
    #expect(await sessionRepository.records().last?.termination == .open)

    let discardOperation = fixture.owner.beginReturn()
    #expect(await fixture.owner.discardUnsavedChangesAndFinishReturn(
        operationID: discardOperation
    ) == .saved)
    #expect(await sessionRepository.abandonedIDs() == [visitID])
    #expect(fixture.applicator.returnCommitCount == 1)
    #expect(fixture.owner.currentVisitID == nil)
}

@MainActor
@Test
func practiceLaunchStopsBeforePreparationWhenPreviousProgressCannotBeSaved() async {
    let fixture = makePracticeLaunchFixture()
    fixture.applicator.clearStatus = .failed(message: "disk full")
    fixture.owner.request(songID: fixture.songA)

    await fixture.owner.activateCurrentRequest()

    guard case let .failure(failure) = fixture.owner.state else {
        Issue.record("Expected a typed progress-save failure")
        return
    }
    #expect(failure.code == .practiceProgressSaveFailed)
    #expect(failure.diagnosticEvent.category == .persistence)
    #expect(await fixture.preparation.requestedSongIDs().isEmpty)
    #expect(fixture.applicator.appliedSongIDs.isEmpty)
    #expect(await fixture.reporter.events.last == failure.diagnosticEvent)
}

@MainActor
@Test
func practiceLaunchPassesExactRestorePolicyBeforeSessionApply() async {
    let songID = fixtureSongA
    let fixture = makePracticeLaunchFixture(
        progresses: [makeLaunchProgress(songID: songID, revision: songID.uuidString)]
    )
    fixture.owner.request(songID: songID)

    await fixture.owner.activateCurrentRequest()

    #expect(fixture.applicator.restorePolicies == [.exactAvailable])
}

@MainActor
@Test
func practiceLaunchPassesHistoricalPreferencesWithoutStructuralState() async {
    let songID = fixtureSongA
    let fixture = makePracticeLaunchFixture(
        progresses: [makeLaunchProgress(
            songID: songID,
            revision: "previous",
            handMode: .left,
            tempoScale: 0.6,
            loopEnabled: true,
            requiredSuccesses: 4
        )]
    )
    fixture.owner.request(songID: songID)

    await fixture.owner.activateCurrentRequest()

    #expect(fixture.applicator.restorePolicies == [
        .historicalPreferences(PracticeHistoricalPreferences(
            handMode: .left,
            tempoScale: 0.6,
            loopEnabled: true,
            requiredSuccesses: 4
        )),
    ])
}

@MainActor
@Test
func corruptedPracticeHistoryKeepsScoreReadyButBlocksRoundStart() async throws {
    let fixture = makePracticeLaunchFixture(
        historyResultOverride: .corrupted(description: "invalid progress document")
    )
    fixture.owner.request(songID: fixture.songA)

    await fixture.owner.activateCurrentRequest()

    let failure = try #require(fixture.owner.progressAccessFailure)
    #expect(failure.code == .practiceProgressStoreCorrupted)
    #expect(failure.recoveryAction == .backupAndResetCorruptedProgress)
    #expect(fixture.owner.state == .ready(PracticeSongIdentity(
        songID: fixture.songA,
        scoreRevision: fixture.songA.uuidString
    )))
    #expect(fixture.applicator.restorePolicies == [.freshDefaults])
    #expect(fixture.applicator.guidingStartBlocks == [true])
    #expect(await fixture.preparation.requestedSongIDs() == [fixture.songA])
    #expect(await fixture.metadataRepository.metadata.isEmpty)
    #expect(await fixture.reporter.events.contains { $0.code == .practiceProgressStoreCorrupted })
}

@MainActor
@Test
func confirmedCorruptionRecoveryReReadsStoreBeforePreparing() async {
    let fixture = makePracticeLaunchFixture(
        historyResultOverride: .corrupted(description: "invalid progress document")
    )
    fixture.owner.request(songID: fixture.songA)
    await fixture.owner.activateCurrentRequest()

    await fixture.owner.recoverCorruptedProgress()

    #expect(fixture.owner.state == .ready(PracticeSongIdentity(
        songID: fixture.songA,
        scoreRevision: fixture.songA.uuidString
    )))
    #expect(await fixture.preparation.requestedSongIDs() == [fixture.songA, fixture.songA])
    #expect(await fixture.metadataRepository.recoveryCount == 1)
    #expect(fixture.owner.progressAccessFailure == nil)
    #expect(fixture.applicator.guidingStartBlocks == [true, false])
    #expect(await fixture.reporter.events.contains { $0.code == .practiceProgressStoreReset })
}

@MainActor
@Test
func unavailablePracticeStoreKeepsScoreReadyWithoutOfferingDestructiveReset() async throws {
    let fixture = makePracticeLaunchFixture(
        historyResultOverride: .unavailable(description: "NSCocoaErrorDomain#640")
    )
    fixture.owner.request(songID: fixture.songA)

    await fixture.owner.activateCurrentRequest()

    let failure = try #require(fixture.owner.progressAccessFailure)
    #expect(failure.code == .practiceProgressStoreUnavailable)
    #expect(failure.recoveryAction == .retry)
    #expect(fixture.owner.state == .ready(PracticeSongIdentity(
        songID: fixture.songA,
        scoreRevision: fixture.songA.uuidString
    )))
    #expect(await fixture.preparation.requestedSongIDs() == [fixture.songA])
    #expect(fixture.applicator.appliedSongIDs == [fixture.songA])
    #expect(fixture.applicator.guidingStartBlocks == [true])
    #expect(await fixture.metadataRepository.metadata.isEmpty)
}

@MainActor
@Test
func corruptionRecoveryCannotResurrectRequestAfterReturnStarts() async {
    let songID = UUID()
    let repository = RecordingPracticeLaunchProgressRepository(
        historyResultOverride: .corrupted(description: "invalid progress document")
    )
    let recovery = ControlledPracticeProgressRecovery()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: PracticeLaunchRecordingApplicator(applyOutcome: .applied),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: repository,
        progressRecovery: recovery
    )
    owner.request(songID: songID)
    await owner.activateCurrentRequest()

    let recoveryTask = Task { @MainActor in await owner.recoverCorruptedProgress() }
    await recovery.waitUntilRequested()
    _ = owner.beginReturn()
    await recovery.resume()
    await recoveryTask.value

    #expect(owner.requestedSongID == nil)
    #expect(owner.activationIdentity == nil)
}

@MainActor
@Test
func staleCorruptedHistoryDoesNotRecordWarningAfterRequestChanges() async {
    let fixture = makePracticeLaunchFixture(
        historyResultOverride: .corrupted(description: "invalid progress document"),
        historyDelay: .milliseconds(50)
    )
    fixture.owner.request(songID: fixture.songA)
    let activation = Task { @MainActor in
        await fixture.owner.activateCurrentRequest()
    }
    await fixture.metadataRepository.waitUntilHistoryRequested()

    fixture.owner.request(songID: fixture.songB)
    await activation.value

    let failures = await fixture.reporter.events.filter { $0.code == .practiceProgressStoreCorrupted }
    #expect(failures.isEmpty)
    #expect(fixture.owner.state == .requested(songID: fixture.songB))
}

@MainActor
@Test
func practiceLaunchLatestAtoBtoARequestWins() async throws {
    let songA = UUID()
    let songB = UUID()
    let fixture = makePracticeLaunchFixture(
        songA: songA,
        songB: songB,
        delays: [songA: .milliseconds(40), songB: .milliseconds(30)]
    )

    fixture.owner.request(songID: songA)
    let firstA = Task { @MainActor in await fixture.owner.activateCurrentRequest() }
    try await Task.sleep(for: .milliseconds(5))
    fixture.owner.request(songID: songB)
    let b = Task { @MainActor in await fixture.owner.activateCurrentRequest() }
    try await Task.sleep(for: .milliseconds(5))
    fixture.owner.request(songID: songA)
    await fixture.owner.activateCurrentRequest()
    await firstA.value
    await b.value

    #expect(fixture.owner.state == .ready(PracticeSongIdentity(songID: songA, scoreRevision: songA.uuidString)))
    #expect(fixture.applicator.appliedSongIDs == [songA])
    #expect(await fixture.reporter.events.filter { $0.severity == .error }.isEmpty)
}

@MainActor
@Test
func practiceLaunchRejectsPreparedPracticeWithoutMeasureStructure() async {
    let fixture = makePracticeLaunchFixture(includeMeasureSpans: false)
    fixture.owner.request(songID: fixture.songA)

    await fixture.owner.activateCurrentRequest()

    guard case let .failure(failure) = fixture.owner.state else {
        Issue.record("Expected a typed launch failure")
        return
    }
    #expect(failure.code == .practiceMissingMeasureStructure)
    #expect(fixture.applicator.appliedSongIDs.isEmpty)
    #expect(await fixture.reporter.events.last == failure.diagnosticEvent)
}

@MainActor
@Test
func practiceLaunchFailureRetryCreatesNewFailureIdentity() async {
    let fixture = makePracticeLaunchFixture(error: PracticePreparationError.noPlayableNotes)
    fixture.owner.request(songID: fixture.songA)
    await fixture.owner.activateCurrentRequest()
    guard case let .failure(first) = fixture.owner.state else {
        Issue.record("Expected first failure")
        return
    }

    await fixture.owner.retry()

    guard case let .failure(second) = fixture.owner.state else {
        Issue.record("Expected retry failure")
        return
    }
    #expect(second.id != first.id)
    #expect(await fixture.reporter.events.count(where: { $0.severity == .error }) == 2)
}

@MainActor
@Test
func cancelledPracticeLaunchDoesNotPublishOrLogStaleFailure() async throws {
    let fixture = makePracticeLaunchFixture(
        delays: [fixtureSongA: .milliseconds(40)],
        errors: [fixtureSongA: PracticePreparationError.noPlayableNotes]
    )
    fixture.owner.request(songID: fixture.songA)
    let activation = Task { @MainActor in await fixture.owner.activateCurrentRequest() }
    try await Task.sleep(for: .milliseconds(5))

    await fixture.owner.suspendForInactiveScene()
    await activation.value

    #expect(fixture.owner.state == .requested(songID: fixture.songA))
    #expect(await fixture.reporter.events.filter { $0.severity == .error }.isEmpty)
    #expect(fixture.applicator.suspendCount == 1)
}

@MainActor
@Test
func inactivePracticeLaunchReactivatesItsRegisteredRequest() async {
    let fixture = makePracticeLaunchFixture()
    fixture.owner.request(songID: fixture.songA)
    await fixture.owner.suspendForInactiveScene()

    await fixture.owner.activateCurrentRequest()

    #expect(await fixture.preparation.requestedSongIDs() == [fixture.songA])
    #expect(fixture.owner.state == .ready(PracticeSongIdentity(songID: fixture.songA, scoreRevision: fixture.songA.uuidString)))
}

@MainActor
@Test
func practiceLaunchReturnFinishIsIdempotentAndRejectsStaleOperation() async {
    let fixture = makePracticeLaunchFixture()
    fixture.owner.request(songID: fixture.songA)
    let clearCountBeforeReturn = fixture.applicator.clearCount
    let operationID = fixture.owner.beginReturn()

    await fixture.owner.finishReturn(operationID: UUID())
    await fixture.owner.finishReturn(operationID: operationID)
    await fixture.owner.finishReturn(operationID: operationID)

    #expect(fixture.owner.state == .requested(songID: fixture.songA))
    #expect(fixture.owner.requestedSongID == nil)
    #expect(fixture.owner.activationIdentity == nil)
    #expect(fixture.applicator.clearCount == clearCountBeforeReturn)
    #expect(fixture.applicator.returnCommitCount == 1)
}

@MainActor
@Test
func successfulPracticeReturnDoesNotReuseFallibleLaunchClearAfterRecorderFinalize() async throws {
    let sessionRepository = PracticeLaunchSessionRepository()
    let recorder = PracticeSessionRecorder(repository: sessionRepository)
    let fixture = makePracticeLaunchFixture(sessionRecorder: recorder)
    fixture.owner.request(songID: fixture.songA)
    await fixture.owner.activateCurrentRequest()
    await recorder.setGuiding(true)
    _ = await recorder.checkpoint()
    let clearCountBeforeReturn = fixture.applicator.clearCount
    fixture.applicator.clearStatus = .failed(message: "disk full")

    let operationID = fixture.owner.beginReturn()
    let status = await fixture.owner.finishReturn(operationID: operationID)

    #expect(status == .saved)
    #expect(fixture.owner.requestedSongID == nil)
    #expect(fixture.applicator.clearCount == clearCountBeforeReturn)
    #expect(fixture.applicator.returnCommitCount == 1)
    #expect(try #require(await sessionRepository.records().last).termination == .normal)
}

@MainActor
@Test
func abortingPracticeReturnRestoresARequestedLaunch() {
    let fixture = makePracticeLaunchFixture()
    fixture.owner.request(songID: fixture.songA)

    let operationID = fixture.owner.beginReturn()
    fixture.owner.abortReturn(operationID: operationID)

    #expect(fixture.owner.state == .requested(songID: fixture.songA))
    #expect(fixture.owner.requestedSongID == fixture.songA)
    #expect(fixture.owner.activationIdentity?.songID == fixture.songA)
}

@MainActor
@Test
func practiceLaunchReturnKeepsReadyPresentationUntilWindowCloses() async {
    let fixture = makePracticeLaunchFixture()
    fixture.owner.request(songID: fixture.songA)
    await fixture.owner.activateCurrentRequest()
    let readyState = fixture.owner.state

    let operationID = fixture.owner.beginReturn()
    await fixture.owner.finishReturn(operationID: operationID)

    #expect(fixture.owner.state == readyState)
    #expect(fixture.owner.requestedSongID == nil)
    #expect(fixture.owner.activationIdentity == nil)
}

@MainActor
@Test
func systemCloseWaitsForCancelledActivationToActuallyFinish() async {
    let songID = UUID()
    let preparation = ControlledPracticeLaunchPreparationService()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: preparation,
        applicator: PracticeLaunchRecordingApplicator(applyOutcome: .applied),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )
    owner.request(songID: songID)
    let activation = Task { @MainActor in await owner.activateCurrentRequest() }
    await preparation.waitUntilRequested(songID: songID)
    let completion = PracticeLaunchCompletionProbe()

    let close = Task { @MainActor in
        await owner.closeForSystemDisappear()
        await completion.markCompleted()
    }
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    let completedBeforeDependencySettled = await completion.isCompleted
    await preparation.resume(songID: songID)
    await close.value
    await activation.value

    #expect(completedBeforeDependencySettled == false)
    #expect(owner.requestedSongID == nil)
}

@MainActor
@Test
func discardReturnWaitsForCancelledMetadataWriteToActuallyFinish() async {
    let songID = UUID()
    let repository = SuspendedMetadataPracticeLaunchRepository()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: PracticeLaunchRecordingApplicator(applyOutcome: .applied),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: repository
    )
    owner.request(songID: songID)
    await owner.activateCurrentRequest()
    await repository.waitUntilMetadataWriteStarts()
    let operationID = owner.beginReturn()
    let completion = PracticeLaunchCompletionProbe()

    let discard = Task { @MainActor in
        let status = await owner.discardUnsavedChangesAndFinishReturn(operationID: operationID)
        await completion.markCompleted()
        return status
    }
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    let completedBeforeDependencySettled = await completion.isCompleted
    await repository.resumeMetadataWrite()

    #expect(completedBeforeDependencySettled == false)
    #expect(await discard.value == .saved)
    #expect(owner.currentVisitID == nil)
}

@MainActor
@Test
func practiceLaunchReportsRepairedSavedConfigurationButStillBecomesReady() async {
    let fixture = makePracticeLaunchFixture(applyOutcome: .appliedWithRepairedSavedState)
    fixture.owner.request(songID: fixture.songA)

    await fixture.owner.activateCurrentRequest()

    #expect(fixture.owner.state == .ready(PracticeSongIdentity(songID: fixture.songA, scoreRevision: fixture.songA.uuidString)))
    #expect(await fixture.reporter.events.contains { $0.code == .practiceSavedConfigurationRepaired })
}

@MainActor
@Test
func practiceLaunchReportsRepairPersistenceFailureWithoutClaimingSuccess() async {
    let fixture = makePracticeLaunchFixture(applyOutcome: .appliedWithUnpersistedRepair)
    fixture.owner.request(songID: fixture.songA)

    await fixture.owner.activateCurrentRequest()

    #expect(fixture.owner.state == .ready(PracticeSongIdentity(songID: fixture.songA, scoreRevision: fixture.songA.uuidString)))
    #expect(await fixture.reporter.events.contains { $0.code == .practiceSavedConfigurationRepairFailed })
    #expect(await fixture.reporter.events.contains { $0.code == .practiceSavedConfigurationRepaired } == false)
}

@MainActor
@Test
func metadataWriteFailureKeepsReadyAndRecordsPrivateSafeWarning() async throws {
    let songID = UUID()
    let repository = RecordingPracticeLaunchProgressRepository(
        metadataError: CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: "/Users/private/progress.json"])
    )
    let reporter = InMemoryDiagnosticsReporter()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: PracticeLaunchRecordingApplicator(applyOutcome: .applied),
        diagnosticsReporter: reporter,
        progressRepository: repository
    )
    owner.request(songID: songID)

    await owner.activateCurrentRequest()
    let event = try await waitForLaunchDiagnostic(
        reporter,
        code: .practiceScoreMetadataWriteFailed
    )

    #expect(owner.state == .ready(PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString)))
    #expect(event.songID == songID)
    #expect(event.scoreRevision == songID.uuidString)
    #expect(event.reason.contains(songID.uuidString))
    #expect(event.reason.contains("measureCount=1"))
    #expect(event.reason.contains("/Users/") == false)
    let history = try #require(await repository.loadedHistory(songID: songID))
    let entry = makePracticeLaunchEntry(songID: songID)
    #expect(try await SongPracticeLibrarySnapshotBuilder().build(
        entry: entry,
        historyResult: .loaded(history),
        viewedAt: Date(timeIntervalSince1970: 200),
        viewingTimeZone: #require(TimeZone(secondsFromGMT: 0)),
        canResetCorruption: false
    ) == .invitation(SongPracticeLibrarySelectionIdentity(
        songID: entry.id,
        scoreFileVersionID: entry.scoreFileVersionID
    )))
}

@MainActor
@Test
func metadataWriteFailureWithOldProgressStillInvitesUntilARealSessionExists() async throws {
    let songID = UUID()
    let attemptedAt = Date(timeIntervalSince1970: 42)
    let oldProgress = SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: "old"),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0),
            handMode: .both,
            state: .learning,
            failedAttempts: 1,
            lastAttemptAt: attemptedAt
        )],
        updatedAt: attemptedAt
    )
    let repository = RecordingPracticeLaunchProgressRepository(
        metadataError: CocoaError(.fileWriteOutOfSpace),
        progresses: [oldProgress]
    )
    let reporter = InMemoryDiagnosticsReporter()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: PracticeLaunchRecordingApplicator(applyOutcome: .applied),
        diagnosticsReporter: reporter,
        progressRepository: repository
    )
    owner.request(songID: songID)

    await owner.activateCurrentRequest()
    _ = try await waitForLaunchDiagnostic(reporter, code: .practiceScoreMetadataWriteFailed)

    let history = try #require(await repository.loadedHistory(songID: songID))
    let entry = makePracticeLaunchEntry(songID: songID)
    #expect(try await SongPracticeLibrarySnapshotBuilder().build(
        entry: entry,
        historyResult: .loaded(history),
        viewedAt: Date(timeIntervalSince1970: 200),
        viewingTimeZone: #require(TimeZone(secondsFromGMT: 0)),
        canResetCorruption: false
    ) == .invitation(SongPracticeLibrarySelectionIdentity(
        songID: entry.id,
        scoreFileVersionID: entry.scoreFileVersionID
    )))
}

@MainActor
@Test
func prepareOrApplyRejectionDoesNotWriteMetadata() async {
    let songID = UUID()
    let prepareRepository = RecordingPracticeLaunchProgressRepository()
    let prepareFailure = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [songID: .noPlayableNotes],
            includeMeasureSpans: true
        ),
        applicator: PracticeLaunchRecordingApplicator(applyOutcome: .applied),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: prepareRepository
    )
    prepareFailure.request(songID: songID)
    await prepareFailure.activateCurrentRequest()

    let applyRepository = RecordingPracticeLaunchProgressRepository()
    let applyRejection = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: RejectOncePracticeLaunchApplicator(),
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: applyRepository
    )
    applyRejection.request(songID: songID)
    await applyRejection.activateCurrentRequest()
    await Task.yield()

    #expect(await prepareRepository.metadata.isEmpty)
    #expect(await applyRepository.metadata.isEmpty)
}

@MainActor
@Test
func successfulApplyBecomingStaleStillWritesMetadataWithoutPublishingReady() async {
    let songA = UUID()
    let songB = UUID()
    let applicator = AppliedThenSuspendedPracticeLaunchApplicator()
    let repository = RecordingPracticeLaunchProgressRepository()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songA, songB]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: applicator,
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: repository
    )
    owner.request(songID: songA)
    let first = Task { @MainActor in await owner.activateCurrentRequest() }
    await applicator.waitUntilApplyStarted()

    owner.request(songID: songB)
    applicator.resumeApply()
    await first.value
    await repository.waitForMetadataCount(1)

    #expect(owner.state == .requested(songID: songB))
    #expect(await repository.metadata.map(\.songID) == [songA])
}

@MainActor
@Test
func newRequestWhileResolveIsSuspendedCannotPublishOldGeneration() async {
    let songA = UUID()
    let songB = UUID()
    let resolver = ControlledPracticeLaunchResolver(songIDs: [songA, songB])
    let preparation = PracticeLaunchPreparationService(delays: [:], errors: [:], includeMeasureSpans: true)
    let applicator = PracticeLaunchRecordingApplicator(applyOutcome: .applied)
    let reporter = InMemoryDiagnosticsReporter()
    let owner = PracticeLaunchViewModel(
        resolver: resolver,
        preparationService: preparation,
        applicator: applicator,
        diagnosticsReporter: reporter,
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )

    owner.request(songID: songA)
    let first = Task { @MainActor in await owner.activateCurrentRequest() }
    await resolver.waitUntilRequested(songID: songA)
    owner.request(songID: songB)
    let second = Task { @MainActor in await owner.activateCurrentRequest() }
    await resolver.waitUntilRequested(songID: songB)

    await resolver.resume(songID: songB)
    await second.value
    await resolver.resume(songID: songA)
    await first.value

    #expect(owner.state == .ready(PracticeSongIdentity(songID: songB, scoreRevision: songB.uuidString)))
    #expect(await preparation.requestedSongIDs() == [songB])
    #expect(applicator.appliedSongIDs == [songB])
    #expect(await reporter.events.filter { $0.severity == .error }.isEmpty)
}

@MainActor
@Test
func returnWhilePrepareIsSuspendedCannotApplyOrPublishFailure() async {
    let songID = UUID()
    let preparation = ControlledPracticeLaunchPreparationService()
    let applicator = PracticeLaunchRecordingApplicator(applyOutcome: .applied)
    let reporter = InMemoryDiagnosticsReporter()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: preparation,
        applicator: applicator,
        diagnosticsReporter: reporter,
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )
    owner.request(songID: songID)
    let activation = Task { @MainActor in await owner.activateCurrentRequest() }
    await preparation.waitUntilRequested(songID: songID)

    let operationID = owner.beginReturn()
    await preparation.resume(songID: songID)
    await activation.value
    await owner.finishReturn(operationID: operationID)

    #expect(owner.state == .loading(songID: songID))
    #expect(owner.requestedSongID == nil)
    #expect(owner.activationIdentity == nil)
    #expect(applicator.appliedSongIDs.isEmpty)
    #expect(await reporter.events.filter { $0.severity == .error }.isEmpty)
}

@MainActor
@Test
func sceneInactiveWhileApplyIsSuspendedCannotLeakOldReadyState() async {
    let songID = UUID()
    let applicator = ControlledPracticeLaunchApplicator()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: applicator,
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )
    owner.request(songID: songID)
    let activation = Task { @MainActor in await owner.activateCurrentRequest() }
    await applicator.waitUntilApplyStarted()

    let suspension = Task { @MainActor in
        await owner.suspendForInactiveScene()
    }
    for _ in 0 ..< 20 {
        await Task.yield()
    }
    applicator.resumeApply()
    await suspension.value
    await activation.value

    #expect(owner.state == .requested(songID: songID))
    #expect(applicator.appliedSongIDs.isEmpty)
    #expect(applicator.suspendCount == 1)
}

@MainActor
@Test
func missingLibraryMetadataProducesTypedFailureWithoutApply() async {
    let missingID = UUID()
    let applicator = PracticeLaunchRecordingApplicator(applyOutcome: .applied)
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: []),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: applicator,
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )
    owner.request(songID: missingID)

    await owner.activateCurrentRequest()

    guard case let .failure(failure) = owner.state else {
        Issue.record("Expected missing metadata failure")
        return
    }
    #expect(failure.code == .practiceScoreFileNotFound)
    #expect(failure.file == nil)
    #expect(applicator.appliedSongIDs.isEmpty)
}

@MainActor
@Test
func consecutivePracticeLaunchRetriesUseFreshGenerationsAndEventuallyReady() async {
    let songID = UUID()
    let preparation = SequencedPracticeLaunchPreparationService(
        results: [
            .failure(.noPlayableNotes),
            .failure(.noPlayableNotes),
            .success,
        ]
    )
    let applicator = PracticeLaunchRecordingApplicator(applyOutcome: .applied)
    let reporter = InMemoryDiagnosticsReporter()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: preparation,
        applicator: applicator,
        diagnosticsReporter: reporter,
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )
    owner.request(songID: songID)
    await owner.activateCurrentRequest()
    guard case let .failure(firstFailure) = owner.state else {
        Issue.record("Expected first failure")
        return
    }
    await owner.retry()
    guard case let .failure(secondFailure) = owner.state else {
        Issue.record("Expected second failure")
        return
    }

    await owner.retry()

    #expect(firstFailure.id != secondFailure.id)
    #expect(owner.state == .ready(PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString)))
    #expect(await preparation.requestCount == 3)
    #expect(applicator.appliedSongIDs == [songID])
    #expect(await reporter.events.count(where: { $0.severity == .error }) == 2)
}

@MainActor
@Test
func currentApplyRejectionRequeuesRequestInsteadOfRemainingLoading() async {
    let songID = UUID()
    let applicator = RejectOncePracticeLaunchApplicator()
    let owner = PracticeLaunchViewModel(
        resolver: PracticeLaunchResolver(songIDs: [songID]),
        preparationService: PracticeLaunchPreparationService(
            delays: [:],
            errors: [:],
            includeMeasureSpans: true
        ),
        applicator: applicator,
        diagnosticsReporter: InMemoryDiagnosticsReporter(),
        progressRepository: RecordingPracticeLaunchProgressRepository()
    )
    owner.request(songID: songID)

    await owner.activateCurrentRequest()
    #expect(owner.state == .requested(songID: songID))

    await owner.activateCurrentRequest()
    #expect(owner.state == .ready(PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString)))
    #expect(applicator.applyCount == 2)
}

private let fixtureSongA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

@MainActor
private func makePracticeLaunchFixture(
    songA: UUID = fixtureSongA,
    songB: UUID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    delays: [UUID: Duration] = [:],
    error: PracticePreparationError? = nil,
    errors: [UUID: PracticePreparationError] = [:],
    includeMeasureSpans: Bool = true,
    applyOutcome: PracticeLaunchApplyOutcome = .applied,
    progresses: [SongPracticeProgress] = [],
    historyResultOverride: PracticeSongHistoryLoadResult? = nil,
    historyDelay: Duration = .zero,
    sessionRecorder: PracticeSessionRecorder? = nil
) -> PracticeLaunchFixture {
    let resolver = PracticeLaunchResolver(songIDs: [songA, songB])
    let preparation = PracticeLaunchPreparationService(
        delays: delays,
        errors: errors.merging(error.map { [songA: $0] } ?? [:]) { _, replacement in replacement },
        includeMeasureSpans: includeMeasureSpans
    )
    let applicator = PracticeLaunchRecordingApplicator(applyOutcome: applyOutcome)
    let reporter = InMemoryDiagnosticsReporter()
    let metadataRepository = RecordingPracticeLaunchProgressRepository(
        progresses: progresses,
        historyResultOverride: historyResultOverride,
        historyDelay: historyDelay
    )
    return PracticeLaunchFixture(
        owner: PracticeLaunchViewModel(
            resolver: resolver,
            preparationService: preparation,
            applicator: applicator,
            diagnosticsReporter: reporter,
            progressRepository: metadataRepository,
            progressRecovery: metadataRepository,
            sessionRecorder: sessionRecorder
        ),
        preparation: preparation,
        applicator: applicator,
        reporter: reporter,
        metadataRepository: metadataRepository,
        songA: songA,
        songB: songB
    )
}

private actor PracticeLaunchSessionRepository: PracticeSessionRepositoryProtocol {
    private var storedRecords: [PracticeSessionRecord] = []
    private var failuresRemaining = 0
    private var abandonedSessionIDs: [UUID] = []

    func upsert(_ session: PracticeSessionRecord) throws {
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw CocoaError(.fileWriteOutOfSpace)
        }
        storedRecords.append(session)
    }

    func abandonLiveSession(id: UUID) {
        abandonedSessionIDs.append(id)
    }

    func failNextWrites(_ count: Int) {
        failuresRemaining = max(0, count)
    }

    func records() -> [PracticeSessionRecord] {
        storedRecords
    }

    func abandonedIDs() -> [UUID] {
        abandonedSessionIDs
    }
}

@MainActor
private struct PracticeLaunchFixture {
    let owner: PracticeLaunchViewModel
    let preparation: PracticeLaunchPreparationService
    let applicator: PracticeLaunchRecordingApplicator
    let reporter: InMemoryDiagnosticsReporter
    let metadataRepository: RecordingPracticeLaunchProgressRepository
    let songA: UUID
    let songB: UUID
}

private actor RecordingPracticeLaunchProgressRepository:
    PracticeProgressRepositoryProtocol,
    PracticeProgressRecoveryProtocol
{
    private(set) var metadata: [SongScorePracticeMetadata] = []
    private var progresses: [SongPracticeProgress]
    let metadataError: Error?
    private var historyResultOverride: PracticeSongHistoryLoadResult?
    let historyDelay: Duration
    private var historyRequestCount = 0
    private(set) var recoveryCount = 0

    init(
        metadataError: Error? = nil,
        progresses: [SongPracticeProgress] = [],
        historyResultOverride: PracticeSongHistoryLoadResult? = nil,
        historyDelay: Duration = .zero
    ) {
        self.metadataError = metadataError
        self.progresses = progresses
        self.historyResultOverride = historyResultOverride
        self.historyDelay = historyDelay
    }

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for songID: UUID) async -> PracticeSongHistoryLoadResult {
        historyRequestCount += 1
        if historyDelay != .zero {
            try? await Task.sleep(for: historyDelay)
        }
        if let historyResultOverride { return historyResultOverride }
        return .loaded(PracticeSongHistory(
            songID: songID,
            progresses: progresses.filter { $0.identity.songID == songID },
            scoreMetadata: metadata.filter { $0.songID == songID },
            sessions: []
        ))
    }

    func upsert(_ progress: SongPracticeProgress) {
        progresses.removeAll(where: { $0.identity == progress.identity })
        progresses.append(progress)
    }

    func upsert(_ metadata: SongScorePracticeMetadata) throws {
        if let metadataError { throw metadataError }
        self.metadata.append(metadata)
    }

    func remove(songID _: UUID) {}

    func recoverFromCorruption() -> PracticeProgressRecoveryResult {
        guard case .corrupted = historyResultOverride else { return .notNeeded }
        historyResultOverride = nil
        recoveryCount += 1
        return .recovered(backupURL: URL(fileURLWithPath: "/test-only-backup.json"))
    }

    func waitForMetadataCount(_ count: Int) async {
        while metadata.count < count {
            await Task.yield()
        }
    }

    func loadedHistory(songID: UUID) async -> PracticeSongHistory? {
        guard case let .loaded(history) = await history(for: songID) else { return nil }
        return history
    }

    func waitUntilHistoryRequested() async {
        while historyRequestCount == 0 {
            await Task.yield()
        }
    }
}

private actor ControlledPracticeProgressRecovery: PracticeProgressRecoveryProtocol {
    private var continuation: CheckedContinuation<PracticeProgressRecoveryResult, Error>?
    private var isRequested = false

    func recoverFromCorruption() async throws -> PracticeProgressRecoveryResult {
        isRequested = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        while isRequested == false {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume(returning: .recovered(
            backupURL: URL(fileURLWithPath: "/test-only-backup.json")
        ))
        continuation = nil
    }
}

private actor SuspendedMetadataPracticeLaunchRepository: PracticeProgressRepositoryProtocol {
    private var metadataContinuation: CheckedContinuation<Void, Never>?
    private var didStartMetadataWrite = false

    func load() -> PracticeProgressLoadResult {
        .loaded(PracticeProgressDocument())
    }

    func progress(for _: PracticeSongIdentity) -> SongPracticeProgress? {
        nil
    }

    func history(for songID: UUID) -> PracticeSongHistoryLoadResult {
        .loaded(PracticeSongHistory(songID: songID, progresses: [], scoreMetadata: [], sessions: []))
    }

    func upsert(_: SongPracticeProgress) {}
    func upsert(_: SongScorePracticeMetadata) async {
        didStartMetadataWrite = true
        await withCheckedContinuation { metadataContinuation = $0 }
    }

    func remove(songID _: UUID) {}

    func waitUntilMetadataWriteStarts() async {
        while didStartMetadataWrite == false {
            await Task.yield()
        }
    }

    func resumeMetadataWrite() {
        metadataContinuation?.resume()
        metadataContinuation = nil
    }
}

private actor PracticeLaunchCompletionProbe {
    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

private func makeLaunchProgress(
    songID: UUID,
    revision: String,
    handMode: PracticeHandMode = .both,
    tempoScale: Double = 1,
    loopEnabled: Bool = false,
    requiredSuccesses: Int = 1
) -> SongPracticeProgress {
    let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 99)
    let occurrence = PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 99)
    return SongPracticeProgress(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: revision),
        activeConfiguration: PracticeRoundConfiguration(
            passage: PracticePassage(start: occurrence, end: occurrence)!,
            handMode: handMode,
            tempoScale: tempoScale,
            loopEnabled: loopEnabled,
            requiredSuccesses: requiredSuccesses
        ),
        resumePoint: PracticeResumePoint(
            occurrenceID: occurrence,
            stepIndex: 99,
            updatedAt: Date(timeIntervalSince1970: 99)
        ),
        measureFacts: [MeasurePracticeFacts(
            sourceMeasureID: source,
            handMode: handMode,
            state: .stable,
            successfulAttempts: 9
        )],
        updatedAt: Date(timeIntervalSince1970: 99)
    )
}

private func makePracticeLaunchEntry(songID: UUID) -> SongLibraryEntry {
    SongLibraryEntry(
        id: songID,
        displayName: "Song",
        musicXMLFileName: "song.musicxml",
        scoreFileVersionID: songID,
        importedAt: Date(timeIntervalSince1970: 0),
        audioFileName: nil,
        isBundled: true
    )
}

private func waitForLaunchDiagnostic(
    _ reporter: InMemoryDiagnosticsReporter,
    code: DiagnosticCode
) async throws -> DiagnosticEvent {
    for _ in 0 ..< 200 {
        if let event = await reporter.events.first(where: { $0.code == code }) {
            return event
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw CocoaError(.coderReadCorrupt)
}

private actor PracticeLaunchResolver: SongLibraryEntryResolving {
    let entries: [UUID: SongLibraryEntry]

    init(songIDs: [UUID]) {
        entries = Dictionary(uniqueKeysWithValues: songIDs.map { songID in
            (songID, SongLibraryEntry(
                id: songID,
                displayName: songID.uuidString,
                musicXMLFileName: "\(songID).musicxml",
                scoreFileVersionID: songID,
                importedAt: .now,
                audioFileName: nil,
                isBundled: true
            ))
        })
    }

    func resolve(songID: UUID) throws -> ResolvedSongLibraryEntry {
        guard let entry = entries[songID] else {
            throw SongLibraryEntryResolutionError(preparationError: .scoreFileNotFound, diagnosticFileReference: nil)
        }
        return ResolvedSongLibraryEntry(
            entry: entry,
            scoreURL: URL(fileURLWithPath: "/tmp/\(entry.musicXMLFileName)"),
            diagnosticFileReference: DiagnosticFileReference(
                fileName: entry.musicXMLFileName,
                relativePath: "Bundle/\(entry.musicXMLFileName)"
            )
        )
    }
}

private actor ControlledPracticeLaunchResolver: SongLibraryEntryResolving {
    let entries: [UUID: SongLibraryEntry]
    private var continuations: [UUID: CheckedContinuation<ResolvedSongLibraryEntry, Error>] = [:]
    private var requestedSongIDs: Set<UUID> = []

    init(songIDs: [UUID]) {
        entries = Dictionary(uniqueKeysWithValues: songIDs.map { songID in
            (songID, SongLibraryEntry(
                id: songID,
                displayName: songID.uuidString,
                musicXMLFileName: "\(songID).musicxml",
                scoreFileVersionID: songID,
                importedAt: .now,
                audioFileName: nil,
                isBundled: true
            ))
        })
    }

    func resolve(songID: UUID) async throws -> ResolvedSongLibraryEntry {
        requestedSongIDs.insert(songID)
        return try await withCheckedThrowingContinuation { continuation in
            continuations[songID] = continuation
        }
    }

    func waitUntilRequested(songID: UUID) async {
        while requestedSongIDs.contains(songID) == false {
            await Task.yield()
        }
    }

    func resume(songID: UUID) {
        guard let entry = entries[songID] else { return }
        continuations.removeValue(forKey: songID)?.resume(
            returning: ResolvedSongLibraryEntry(
                entry: entry,
                scoreURL: URL(fileURLWithPath: "/tmp/\(entry.musicXMLFileName)"),
                diagnosticFileReference: nil
            )
        )
    }
}

private actor PracticeLaunchPreparationService: PracticePreparationServiceProtocol {
    let delays: [UUID: Duration]
    let errors: [UUID: PracticePreparationError]
    let includeMeasureSpans: Bool
    private var requests: [UUID] = []

    init(
        delays: [UUID: Duration],
        errors: [UUID: PracticePreparationError],
        includeMeasureSpans: Bool
    ) {
        self.delays = delays
        self.errors = errors
        self.includeMeasureSpans = includeMeasureSpans
    }

    func prepare(songID: UUID, from _: URL, file: ImportedMusicXMLFile, options _: PracticePreparationOptions) async throws -> PreparedPractice {
        requests.append(songID)
        if let delay = delays[songID] { try await Task.sleep(for: delay) }
        if let error = errors[songID] { throw error }
        return makePracticeLaunchPreparedPractice(
            songID: songID,
            file: file,
            includeMeasureSpans: includeMeasureSpans
        )
    }

    func requestedSongIDs() -> [UUID] {
        requests
    }
}

private actor ControlledPracticeLaunchPreparationService: PracticePreparationServiceProtocol {
    private var continuations: [UUID: CheckedContinuation<PreparedPractice, Never>] = [:]
    private var files: [UUID: ImportedMusicXMLFile] = [:]

    func prepare(songID: UUID, from _: URL, file: ImportedMusicXMLFile, options _: PracticePreparationOptions) async throws -> PreparedPractice {
        files[songID] = file
        return await withCheckedContinuation { continuation in
            continuations[songID] = continuation
        }
    }

    func waitUntilRequested(songID: UUID) async {
        while continuations[songID] == nil {
            await Task.yield()
        }
    }

    func resume(songID: UUID) {
        guard let file = files[songID] else { return }
        continuations.removeValue(forKey: songID)?.resume(
            returning: makePracticeLaunchPreparedPractice(
                songID: songID,
                file: file,
                includeMeasureSpans: true
            )
        )
    }
}

private actor SequencedPracticeLaunchPreparationService: PracticePreparationServiceProtocol {
    enum Result {
        case failure(PracticePreparationError)
        case success
    }

    private var results: [Result]
    private(set) var requestCount = 0

    init(results: [Result]) {
        self.results = results
    }

    func prepare(songID: UUID, from _: URL, file: ImportedMusicXMLFile, options _: PracticePreparationOptions) throws -> PreparedPractice {
        requestCount += 1
        switch results.removeFirst() {
        case let .failure(error): throw error
        case .success:
            return makePracticeLaunchPreparedPractice(
                songID: songID,
                file: file,
                includeMeasureSpans: true
            )
        }
    }
}

@MainActor
private final class PracticeLaunchRecordingApplicator: PracticeLaunchApplying {
    private(set) var appliedSongIDs: [UUID] = []
    private(set) var restorePolicies: [PracticeLaunchRestorePolicy] = []
    private(set) var clearCount = 0
    private(set) var returnCommitCount = 0
    private(set) var suspendCount = 0
    private(set) var guidingStartBlocks: [Bool] = []
    let applyOutcome: PracticeLaunchApplyOutcome
    var clearStatus: PracticeProgressSaveStatus

    init(
        applyOutcome: PracticeLaunchApplyOutcome,
        clearStatus: PracticeProgressSaveStatus = .saved
    ) {
        self.applyOutcome = applyOutcome
        self.clearStatus = clearStatus
    }

    func applyPreparedPracticeForLaunch(
        _ prepared: PreparedPractice,
        restorePolicy: PracticeLaunchRestorePolicy,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> PracticeLaunchApplyOutcome? {
        guard isCurrent() else { return nil }
        appliedSongIDs.append(prepared.identity.songID)
        restorePolicies.append(restorePolicy)
        return applyOutcome
    }

    func clearPreparedPracticeForLaunch() async -> PracticeProgressSaveStatus {
        clearCount += 1
        return clearStatus
    }

    func commitPreparedPracticeReturn() {
        returnCommitCount += 1
    }

    func setPracticeGuidingStartBlocked(_ isBlocked: Bool) {
        guidingStartBlocks.append(isBlocked)
    }

    func suspendPracticeAndFlushProgress() async {
        suspendCount += 1
    }
}

@MainActor
private final class ControlledPracticeLaunchApplicator: PracticeLaunchApplying {
    private var applyContinuation: CheckedContinuation<Void, Never>?
    private var pendingSongID: UUID?
    private(set) var appliedSongIDs: [UUID] = []
    private(set) var suspendCount = 0

    func applyPreparedPracticeForLaunch(
        _ prepared: PreparedPractice,
        restorePolicy _: PracticeLaunchRestorePolicy,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> PracticeLaunchApplyOutcome? {
        pendingSongID = prepared.identity.songID
        await withCheckedContinuation { continuation in
            applyContinuation = continuation
        }
        guard isCurrent(), let pendingSongID else { return nil }
        appliedSongIDs.append(pendingSongID)
        return .applied
    }

    func waitUntilApplyStarted() async {
        while applyContinuation == nil {
            await Task.yield()
        }
    }

    func resumeApply() {
        applyContinuation?.resume()
        applyContinuation = nil
    }

    func clearPreparedPracticeForLaunch() async -> PracticeProgressSaveStatus {
        .saved
    }

    func commitPreparedPracticeReturn() {}
    func setPracticeGuidingStartBlocked(_: Bool) {}
    func suspendPracticeAndFlushProgress() async {
        suspendCount += 1
    }
}

@MainActor
private final class AppliedThenSuspendedPracticeLaunchApplicator: PracticeLaunchApplying {
    private var continuation: CheckedContinuation<Void, Never>?

    func applyPreparedPracticeForLaunch(
        _: PreparedPractice,
        restorePolicy _: PracticeLaunchRestorePolicy,
        isCurrent _: @escaping @MainActor () -> Bool
    ) async -> PracticeLaunchApplyOutcome? {
        await withCheckedContinuation { continuation = $0 }
        return .applied
    }

    func waitUntilApplyStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resumeApply() {
        continuation?.resume()
        continuation = nil
    }

    func clearPreparedPracticeForLaunch() async -> PracticeProgressSaveStatus {
        .saved
    }

    func commitPreparedPracticeReturn() {}
    func setPracticeGuidingStartBlocked(_: Bool) {}
    func suspendPracticeAndFlushProgress() async {}
}

@MainActor
private final class RejectOncePracticeLaunchApplicator: PracticeLaunchApplying {
    private(set) var applyCount = 0

    func applyPreparedPracticeForLaunch(
        _: PreparedPractice,
        restorePolicy _: PracticeLaunchRestorePolicy,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> PracticeLaunchApplyOutcome? {
        applyCount += 1
        guard applyCount > 1, isCurrent() else { return nil }
        return .applied
    }

    func clearPreparedPracticeForLaunch() async -> PracticeProgressSaveStatus {
        .saved
    }

    func commitPreparedPracticeReturn() {}
    func setPracticeGuidingStartBlocked(_: Bool) {}
    func suspendPracticeAndFlushProgress() async {}
}

private func makePracticeLaunchPreparedPractice(
    songID: UUID,
    file: ImportedMusicXMLFile,
    includeMeasureSpans: Bool
) -> PreparedPractice {
    PreparedPractice(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1, handAssignment: .unknown)])],
        file: file,
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        pedalTimeline: nil,
        fermataTimeline: nil,
        attributeTimeline: nil,
        highlightGuides: [],
        measureSpans: includeMeasureSpans ? [
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 0,
                startTick: 0,
                endTick: 480
            ),
            MusicXMLMeasureSpan(
                partID: "P1",
                measureNumber: 1,
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                occurrenceIndex: 1,
                startTick: 480,
                endTick: 960
            ),
        ] : [],
        unsupportedNoteCount: 0,
        scoreContext: makeTestPreparedPracticeScoreContext()
    )
}
