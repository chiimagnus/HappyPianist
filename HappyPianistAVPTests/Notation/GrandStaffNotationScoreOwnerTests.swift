import Foundation
import MusicXML
@testable import Notation
import Practice
import SwiftUI
import Testing
@testable import HappyPianistAVP

@Test
@MainActor
func notationOwnerBuildsOnceAcrossOverlayRangeHandTickAndHostChanges() async throws {
    let input = try notationOwnerFixture(revision: "stable").input
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(input)
    let score = try #require(owner.score)
    let original = score.notation
    for hand in [PracticeHandMode.both, .left, .right] {
        for tick in [0.0, 480.0] {
            let plan = try #require(owner.plan)
            let system = try #require(plan.pages.first?.systems.first)
            let presentation = GrandStaffNotationPresentationViewModel().makePresentation(
                system: system, staffSpace: tick == 0 ? 11 : 15, projection: input.projection,
                overlay: ScoreNotationProjection.Overlay(activeEventIDs: [], activeTickRange: 0..<480), practiceHandMode: hand
            )
            #expect(!presentation.notationLayout.rests.isEmpty)
            await owner.load(input)
        }
    }
    #expect(owner.buildCount == 1)
    #expect(owner.score?.notation == original)
    #expect(original.items.allSatisfy { !$0.isHighlighted })
    #expect(original.rests.allSatisfy { !$0.isHighlighted })
}

@Test
@MainActor
func notationOwnerRejectsLateScoreAndCloseCompletion() async throws {
    let scoreA = try notationOwnerFixture(revision: "a")
    let scoreB = try notationOwnerFixture(revision: "b")
    let scoreC = try notationOwnerFixture(revision: "c")
    let builder = ControlledNotationScoreBuilder()
    let owner = GrandStaffNotationPageViewModel(build: { try await builder.build($0) })
    let first = Task { await owner.load(scoreA.input) }
    await TestAsyncWait.until("first notation build") { await builder.hasStarted("a") }
    let second = Task { await owner.load(scoreB.input) }
    await TestAsyncWait.until("second notation build") { await builder.hasStarted("b") }
    await builder.complete(scoreB)
    await second.value
    #expect(owner.score?.input == scoreB.input)
    await builder.complete(scoreA)
    await first.value
    #expect(owner.score?.input == scoreB.input)

    let third = Task { await owner.load(scoreC.input) }
    await TestAsyncWait.until("closing notation build") { await builder.hasStarted("c") }
    owner.clear()
    await builder.complete(scoreC)
    await third.value
    #expect(owner.score == nil)
    #expect(owner.failureMessage == nil)
}

@Test
@MainActor
func notationOwnerCancellationDoesNotPublishAndFormalFactsChangeRebuilds() async throws {
    let score = try notationOwnerFixture(revision: "original")
    let builder = ControlledNotationScoreBuilder()
    let owner = GrandStaffNotationPageViewModel(build: { try await builder.build($0) })
    let request = Task { await owner.load(score.input) }
    await TestAsyncWait.until("cancellable notation build") { await builder.hasStarted("original") }
    request.cancel()
    await builder.complete(score)
    await request.value
    #expect(owner.score == nil)

    let liveOwner = GrandStaffNotationPageViewModel()
    await liveOwner.load(score.input)
    let instrument = MusicXMLLogicalInstrument(
        id: "changed-formal-instrument", memberPartIDs: ["P1"], classification: .piano, evidence: []
    )
    let changed = GrandStaffNotationScoreInput(
        identity: score.input.identity, projection: score.input.projection,
        measureSpans: score.input.measureSpans,
        facts: PracticeNotationScoreFacts(logicalInstrument: instrument, structuralPartID: "P1"),
        attributeTimeline: score.input.attributeTimeline
    )
    await liveOwner.load(changed)
    #expect(liveOwner.buildCount == 2)
    #expect(liveOwner.score?.input == changed)
}

@Test
@MainActor
func notationTestPreparationProvidesMatchingFormalPartsAndClearsFacts() async throws {
    let session = PracticeSessionViewModel(chordAttemptAccumulator: ChordAttemptAccumulator(), sleeper: TaskSleeper())
    session.installTestPerformanceNotes([TestScorePerformanceNote(midiNote: 60, onTick: 0, offTick: 480)])
    let facts = try #require(session.notationScoreFacts)
    #expect(session.measureSpans.allSatisfy { $0.partID == facts.structuralPartID })
    let input = GrandStaffNotationScoreInput(
        identity: try #require(session.songIdentity), projection: try #require(session.notationProjection),
        measureSpans: session.measureSpans, facts: facts, attributeTimeline: session.attributeTimeline
    )
    let owner = GrandStaffNotationPageViewModel()
    await owner.load(input)
    #expect(owner.score != nil)
    #expect(owner.failureMessage == nil)
    session.clearPreparedSong()
    #expect(session.notationScoreFacts == nil)
    session.shutdown()
}

private actor ControlledNotationScoreBuilder {
    private var continuations: [String: CheckedContinuation<GrandStaffNotationScoreLayout, Error>] = [:]

    func build(_ input: GrandStaffNotationScoreInput) async throws -> GrandStaffNotationScoreLayout {
        try await withCheckedThrowingContinuation {
            continuations[input.identity.scoreRevision] = $0
        }
    }

    func hasStarted(_ revision: String) -> Bool { continuations[revision] != nil }

    func complete(_ score: GrandStaffNotationScoreLayout) {
        continuations.removeValue(forKey: score.input.identity.scoreRevision)?.resume(returning: score)
    }
}

private func notationOwnerFixture(revision: String) throws -> GrandStaffNotationScoreLayout {
    let xml = """
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>1</divisions><staves>2</staves>
    <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type><staff>1</staff></note></measure>
    <measure number="2"><note><rest measure="yes"/><duration>4</duration><staff>1</staff></note></measure></part></score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: score), sourceScore: score)
    let fixture = try makeNotationScoreFixture(projection: projection, measureSpans: score.measures)
    let input = GrandStaffNotationScoreInput(
        identity: PracticeSongIdentity(songID: fixture.input.identity.songID, scoreRevision: revision),
        projection: projection, measureSpans: score.measures, facts: fixture.input.facts,
        attributeTimeline: MusicXMLAttributeTimeline(
            timeSignatureEvents: score.timeSignatureEvents, keySignatureEvents: score.keySignatureEvents, clefEvents: score.clefEvents
        )
    )
    return try GrandStaffNotationScoreLayoutService().makeLayout(input: input)
}
