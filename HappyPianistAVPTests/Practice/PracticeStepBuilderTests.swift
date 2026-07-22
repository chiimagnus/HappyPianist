import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func buildStepsGroupsPlanNotesByPerformedOnsetAndPreservesScoreFacts() throws {
    let bassID = sourceNoteID(ordinal: 0, staff: 2, voice: 2)
    let trebleID = sourceNoteID(ordinal: 1, staff: 1, voice: 1)
    let laterID = sourceNoteID(ordinal: 2, staff: 1, voice: 1)
    let plan = performancePlan(notes: [
        performanceNote(
            sourceID: trebleID,
            midiNote: 64,
            performedOnTick: 120,
            staff: 1,
            voice: 1,
            velocity: 88,
            handAssignment: ScoreHandAssignment(hand: .right, provenance: .score),
            fingerings: [MusicXMLFingering(text: "2", provenance: .score)]
        ),
        performanceNote(
            sourceID: bassID,
            midiNote: 48,
            performedOnTick: 120,
            staff: 2,
            voice: 2,
            handAssignment: ScoreHandAssignment(hand: .left, provenance: .heuristic)
        ),
        performanceNote(
            sourceID: laterID,
            midiNote: 67,
            performedOnTick: 240,
            staff: 1,
            voice: 1,
            handAssignment: ScoreHandAssignment(hand: .right, provenance: .score)
        ),
    ])

    let result = PracticeStepBuilder().buildSteps(from: plan)

    #expect(result.unsupportedNoteCount == 0)
    #expect(result.steps.map(\.tick) == [120, 240])
    #expect(result.steps[0].notes.map(\.midiNote) == [48, 64])
    #expect(result.steps[0].notes.map(\.hand) == [.left, .right])
    #expect(result.steps[0].notes.map(\.sourceNoteIDs) == [[bassID], [trebleID]])
    let treble = try #require(result.steps[0].notes.last)
    #expect(treble.handAssignment.provenance == .score)
    #expect(treble.velocity == 88)
    #expect(treble.fingerings.map(\.text) == ["2"])
}

@Test
func buildStepsUsesEachPerformedOnsetAsAnInstantTarget() {
    let plan = performancePlan(
        notes: [
            performanceNote(
                sourceID: sourceNoteID(ordinal: 0),
                midiNote: 60,
                performedOnTick: 0,
                performedOffTick: 480
            ),
            performanceNote(
                sourceID: sourceNoteID(ordinal: 1),
                midiNote: 64,
                performedOnTick: 30,
                performedOffTick: 300
            ),
        ],
        controllers: [
            ScorePerformanceControllerEvent(
                sourceDirectionID: nil,
                performedOccurrenceIndex: 0,
                tick: 15,
                controllerNumber: 64,
                value: 127,
                outputCapabilityRequirement: .continuousControlChange
            ),
        ]
    )

    let result = PracticeStepBuilder().buildSteps(from: plan)

    #expect(result.steps.map(\.tick) == [0, 30])
    #expect(result.steps.map { $0.notes.map(\.midiNote) } == [[60], [64]])
    #expect(result.steps.flatMap(\.notes).allSatisfy { $0.onTickOffset == 0 })
}

@Test
func buildStepsCountsAndFiltersNotesOutsidePianoRange() {
    let plan = performancePlan(notes: [
        performanceNote(sourceID: sourceNoteID(ordinal: 0), midiNote: 10, performedOnTick: 0),
        performanceNote(sourceID: sourceNoteID(ordinal: 1), midiNote: 72, performedOnTick: 120),
        performanceNote(sourceID: sourceNoteID(ordinal: 2), midiNote: 110, performedOnTick: 240),
    ])

    let result = PracticeStepBuilder().buildSteps(from: plan)

    #expect(result.unsupportedNoteCount == 2)
    #expect(result.steps.map(\.tick) == [120])
    #expect(result.steps[0].notes.map(\.midiNote) == [72])
}

@Test
func buildStepsKeepsAllSourceContributorsForOnePhysicalTarget() {
    let firstID = sourceNoteID(ordinal: 0)
    let continuationID = sourceNoteID(ordinal: 1)
    let note = performanceNote(
        sourceID: firstID,
        contributingSourceIDs: [firstID, continuationID],
        midiNote: 60,
        performedOnTick: 0,
        performedOffTick: 960
    )

    let result = PracticeStepBuilder().buildSteps(from: performancePlan(notes: [note]))

    #expect(result.steps.count == 1)
    #expect(result.steps[0].notes.count == 1)
    #expect(result.steps[0].notes[0].sourceNoteIDs == [firstID, continuationID])
}

private func performancePlan(
    notes: [ScorePerformanceNoteEvent],
    controllers: [ScorePerformanceControllerEvent] = []
) -> ScorePerformancePlan {
    ScorePerformancePlan(
        id: ScorePerformancePlanID(rawValue: "practice-step-test"),
        sourceScoreIdentity: ScorePerformanceSourceIdentity(
            songID: UUID(),
            scoreRevision: "test",
            logicalInstrumentID: "piano"
        ),
        order: MusicXMLOrderSelection(requested: .written, applied: .written),
        resolution: ScorePerformanceTickResolution(ticksPerQuarter: 480),
        noteEvents: notes,
        tempoEvents: [],
        controllerEvents: controllers,
        annotations: [],
        approximations: []
    )
}

private func performanceNote(
    sourceID: MusicXMLSourceNoteID,
    contributingSourceIDs: [MusicXMLSourceNoteID]? = nil,
    midiNote: Int,
    performedOnTick: Int,
    performedOffTick: Int? = nil,
    staff: Int = 1,
    voice: Int = 1,
    velocity: UInt8 = 96,
    handAssignment: ScoreHandAssignment = .unknown,
    fingerings: [MusicXMLFingering] = []
) -> ScorePerformanceNoteEvent {
    let performedID = MusicXMLPerformedNoteID(sourceID: sourceID, occurrenceIndex: 0)
    let contributingSourceIDs = contributingSourceIDs ?? [sourceID]
    return ScorePerformanceNoteEvent(
        id: ScorePerformanceNoteEventID(performedNoteID: performedID, generatedOrdinal: nil),
        sourceNoteID: sourceID,
        performedNoteID: performedID,
        contributingSourceNoteIDs: contributingSourceIDs,
        contributingPerformedNoteIDs: contributingSourceIDs.map {
            MusicXMLPerformedNoteID(sourceID: $0, occurrenceIndex: 0)
        },
        purpose: .source,
        writtenOnTick: 0,
        writtenOffTick: 480,
        performedOnTick: performedOnTick,
        performedOffTick: performedOffTick ?? performedOnTick + 480,
        writtenPitch: nil,
        midiNote: midiNote,
        velocityResolution: ScorePerformanceVelocityResolution(
            baseVelocity: Int(velocity),
            curveVelocity: nil,
            articulationDelta: 0,
            unclampedVelocity: Int(velocity),
            velocity: velocity,
            usesGenericDynamicBaseline: false
        ),
        staff: staff,
        voice: voice,
        handAssignment: handAssignment,
        fingerings: fingerings,
        timingProvenance: []
    )
}

private func sourceNoteID(ordinal: Int, staff: Int = 1, voice: Int = 1) -> MusicXMLSourceNoteID {
    MusicXMLSourceNoteID(
        partID: "P1",
        sourceMeasureIndex: 0,
        sourceMeasureNumberToken: "1",
        staff: staff,
        voice: voice,
        sourceOrdinal: ordinal
    )
}
