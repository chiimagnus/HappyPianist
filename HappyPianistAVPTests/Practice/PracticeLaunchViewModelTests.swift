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
    #expect(fixture.owner.state == .ready(PracticeSongIdentity(songID: fixture.songA, scoreRevision: fixture.songA.uuidString)))
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
    #expect(await fixture.reporter.events.filter { $0.severity == .error }.count == 2)
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
    let operationID = fixture.owner.beginReturn()

    await fixture.owner.finishReturn(operationID: UUID())
    await fixture.owner.finishReturn(operationID: operationID)
    await fixture.owner.finishReturn(operationID: operationID)

    #expect(fixture.owner.state == .noRequest)
    #expect(fixture.applicator.clearCount == 1)
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

private let fixtureSongA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

@MainActor
private func makePracticeLaunchFixture(
    songA: UUID = fixtureSongA,
    songB: UUID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    delays: [UUID: Duration] = [:],
    error: PracticePreparationError? = nil,
    errors: [UUID: PracticePreparationError] = [:],
    includeMeasureSpans: Bool = true,
    applyOutcome: PracticeLaunchApplyOutcome = .applied
) -> PracticeLaunchFixture {
    let resolver = PracticeLaunchResolver(songIDs: [songA, songB])
    let preparation = PracticeLaunchPreparationService(
        delays: delays,
        errors: errors.merging(error.map { [songA: $0] } ?? [:]) { _, replacement in replacement },
        includeMeasureSpans: includeMeasureSpans
    )
    let applicator = PracticeLaunchRecordingApplicator(applyOutcome: applyOutcome)
    let reporter = InMemoryDiagnosticsReporter()
    return PracticeLaunchFixture(
        owner: PracticeLaunchViewModel(
            resolver: resolver,
            preparationService: preparation,
            applicator: applicator,
            diagnosticsReporter: reporter
        ),
        preparation: preparation,
        applicator: applicator,
        reporter: reporter,
        songA: songA,
        songB: songB
    )
}

@MainActor
private struct PracticeLaunchFixture {
    let owner: PracticeLaunchViewModel
    let preparation: PracticeLaunchPreparationService
    let applicator: PracticeLaunchRecordingApplicator
    let reporter: InMemoryDiagnosticsReporter
    let songA: UUID
    let songB: UUID
}

private actor PracticeLaunchResolver: SongLibraryEntryResolving {
    let entries: [UUID: SongLibraryEntry]

    init(songIDs: [UUID]) {
        entries = Dictionary(uniqueKeysWithValues: songIDs.map { songID in
            (songID, SongLibraryEntry(
                id: songID,
                displayName: songID.uuidString,
                musicXMLFileName: "\(songID).musicxml",
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

    func prepare(songID: UUID, from _: URL, file: ImportedMusicXMLFile) async throws -> PreparedPractice {
        requests.append(songID)
        if let delay = delays[songID] { try await Task.sleep(for: delay) }
        if let error = errors[songID] { throw error }
        return makePracticeLaunchPreparedPractice(
            songID: songID,
            file: file,
            includeMeasureSpans: includeMeasureSpans
        )
    }

    func requestedSongIDs() -> [UUID] { requests }
}

@MainActor
private final class PracticeLaunchRecordingApplicator: PracticeLaunchApplying {
    private(set) var appliedSongIDs: [UUID] = []
    private(set) var clearCount = 0
    private(set) var suspendCount = 0
    private(set) var leaveCount = 0
    let applyOutcome: PracticeLaunchApplyOutcome

    init(applyOutcome: PracticeLaunchApplyOutcome) {
        self.applyOutcome = applyOutcome
    }

    func applyPreparedPracticeForLaunch(
        _ prepared: PreparedPractice,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> PracticeLaunchApplyOutcome? {
        guard isCurrent() else { return nil }
        appliedSongIDs.append(prepared.identity.songID)
        return applyOutcome
    }

    func clearPreparedPracticeForLaunch() async { clearCount += 1 }
    func suspendPracticeAndFlushProgress() async { suspendCount += 1 }
    func leavePracticeStep() async { leaveCount += 1 }
}

private func makePracticeLaunchPreparedPractice(
    songID: UUID,
    file: ImportedMusicXMLFile,
    includeMeasureSpans: Bool
) -> PreparedPractice {
    PreparedPractice(
        identity: PracticeSongIdentity(songID: songID, scoreRevision: songID.uuidString),
        steps: [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 60, staff: 1)])],
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
        ] : [],
        unsupportedNoteCount: 0
    )
}
