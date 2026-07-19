import Foundation
@testable import HappyPianistAVP

func makeTestPreparedPractice(
    identity: PracticeSongIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
    performanceNotes: [TestScorePerformanceNote] = [
        TestScorePerformanceNote(midiNote: 60, onTick: 0),
    ],
    file: ImportedMusicXMLFile = ImportedMusicXMLFile(
        fileName: "Test",
        storedURL: URL(fileURLWithPath: "/dev/null"),
        importedAt: .now
    ),
    attributeTimeline: MusicXMLAttributeTimeline? = nil,
    highlightGuides: [PianoHighlightGuide] = [],
    measureSpans: [MusicXMLMeasureSpan] = [
        MusicXMLMeasureSpan(
            partID: "P1",
            measureNumber: 1,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            occurrenceIndex: 0,
            startTick: 0,
            endTick: MusicXMLTempoMap.ticksPerQuarter
        ),
    ]
) -> PreparedPractice {
    let sourceScore = makeTestMusicXMLScore(notes: performanceNotes)
    let scoreContext = makeTestPreparedPracticeScoreContext(sourceScore: sourceScore)
    let performancePlan = makeTestScorePerformancePlan(
        identity: identity,
        notes: performanceNotes,
        scoreContext: scoreContext
    )
    let stepProjection = PracticeStepBuilder().buildSteps(from: performancePlan)
    return PreparedPractice(
        identity: identity,
        performancePlan: performancePlan,
        notationProjection: ScoreNotationProjection(
            plan: performancePlan,
            sourceScore: scoreContext.sourceScore
        ),
        steps: stepProjection.steps,
        file: file,
        attributeTimeline: attributeTimeline,
        highlightGuides: highlightGuides,
        measureSpans: measureSpans,
        unsupportedNoteCount: stepProjection.unsupportedNoteCount,
        scoreContext: scoreContext
    )
}

func makeTestScorePerformanceTempoEvents(
    from tempoMap: MusicXMLTempoMap
) -> [ScorePerformanceTempoEvent] {
    tempoMap.performanceEvents().map {
        ScorePerformanceTempoEvent(
            sourceDirectionID: $0.sourceDirectionID,
            performedOccurrenceIndex: $0.performedOccurrenceIndex,
            tick: $0.tick,
            quarterBPM: $0.quarterBPM,
            endTick: $0.endTick,
            endQuarterBPM: $0.endQuarterBPM
        )
    }
}

func makeTestScorePerformanceControllerEvents(
    from pedalTimeline: MusicXMLPedalTimeline
) -> [ScorePerformanceControllerEvent] {
    pedalTimeline.controllerChanges().map {
        ScorePerformanceControllerEvent(
            sourceDirectionID: $0.sourceDirectionID,
            performedOccurrenceIndex: $0.performedOccurrenceIndex,
            tick: $0.tick,
            controllerNumber: $0.controllerNumber,
            value: $0.value,
            outputCapabilityRequirement: .continuousControlChange
        )
    }
}

func makeTestScorePerformancePlan(
    from score: MusicXMLScore,
    expressivity: MusicXMLExpressivityOptions = MusicXMLExpressivityOptions(),
    handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment] = [:],
    performanceTimingEnabled: Bool = false
) -> ScorePerformancePlan {
    // ponytail: fixture scores are single logical pianos; multi-instrument tests must pass an explicit plan.
    let memberPartIDs = Set(score.notes.map(\.partID)).sorted()
    let logicalInstrument = MusicXMLLogicalInstrument(
        id: "test-piano",
        memberPartIDs: memberPartIDs,
        classification: .piano,
        evidence: []
    )
    let timingSchedule = ScoreTimingScheduleBuilder().build(
        notes: score.notes,
        performanceTimingEnabled: performanceTimingEnabled,
        graceEnabled: expressivity.graceEnabled,
        logicalInstruments: [logicalInstrument],
        arpeggiateEnabled: expressivity.arpeggiateEnabled
    )
    let velocityResolver = MusicXMLVelocityResolver(
        dynamicEvents: score.dynamicEvents,
        wedgeEvents: score.wedgeEvents,
        wedgeEnabled: expressivity.wedgeEnabled
    )
    let wordsSemantics = expressivity.wordsSemanticsEnabled
        ? MusicXMLWordsSemanticsInterpreter().interpret(
            wordsEvents: score.wordsEvents,
            tempoEvents: score.tempoEvents
        )
        : nil
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: score.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
        tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
        partID: memberPartIDs.first
    )
    let pedalTimeline = MusicXMLPedalTimeline(
        events: score.pedalEvents + (wordsSemantics?.derivedPedalEvents ?? [])
    )
    let fermataTimeline = expressivity.fermataEnabled
        ? MusicXMLFermataTimeline(fermataEvents: score.fermataEvents, notes: score.notes)
        : nil
    return ScorePerformancePlanBuilder().build(
        sourceIdentity: ScorePerformanceSourceIdentity(
            songID: UUID(),
            scoreRevision: "test",
            logicalInstrumentID: logicalInstrument.id
        ),
        order: MusicXMLOrderSelection(requested: .written, applied: .written),
        logicalInstrument: logicalInstrument,
        notes: score.notes,
        timingSchedule: timingSchedule,
        velocityResolver: velocityResolver,
        expressivity: expressivity,
        handAssignments: handAssignments,
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        tempoAnnotations: wordsSemantics?.tempoAnnotations ?? [],
        fermataTimeline: fermataTimeline
    )
}

struct TestScorePerformanceNote {
    let midiNote: Int
    let velocity: UInt8
    let onTick: Int
    let offTick: Int
    let staff: Int
    let voice: Int
    let handAssignment: ScoreHandAssignment
    let fingeringText: String?

    init(
        midiNote: Int,
        velocity: UInt8 = 96,
        onTick: Int,
        offTick: Int? = nil,
        staff: Int = 1,
        voice: Int = 1,
        handAssignment: ScoreHandAssignment = .unknown,
        fingeringText: String? = nil
    ) {
        self.midiNote = midiNote
        self.velocity = velocity
        self.onTick = onTick
        self.offTick = offTick ?? onTick + MusicXMLTempoMap.ticksPerQuarter
        self.staff = staff
        self.voice = voice
        self.handAssignment = handAssignment
        self.fingeringText = fingeringText
    }
}

func makeTestScorePerformancePlan(
    identity: PracticeSongIdentity = PracticeSongIdentity(songID: UUID(), scoreRevision: "test"),
    notes: [TestScorePerformanceNote],
    scoreContext: PreparedPracticeScoreContext = makeTestPreparedPracticeScoreContext(),
    tempoEvents: [ScorePerformanceTempoEvent] = [],
    controllerEvents: [ScorePerformanceControllerEvent] = [],
    annotations: [ScorePerformanceAnnotation] = []
) -> ScorePerformancePlan {
    let noteEvents = notes.enumerated().map { ordinal, note in
        let sourceID = MusicXMLSourceNoteID(
            partID: scoreContext.structuralPartID,
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: note.staff,
            voice: note.voice,
            sourceOrdinal: ordinal
        )
        let performedID = MusicXMLPerformedNoteID(sourceID: sourceID, occurrenceIndex: 0)
        return ScorePerformanceNoteEvent(
            id: ScorePerformanceNoteEventID(performedNoteID: performedID, generatedOrdinal: nil),
            sourceNoteID: sourceID,
            performedNoteID: performedID,
            contributingSourceNoteIDs: [sourceID],
            contributingPerformedNoteIDs: [performedID],
            purpose: .source,
            writtenOnTick: note.onTick,
            writtenOffTick: note.offTick,
            performedOnTick: note.onTick,
            performedOffTick: note.offTick,
            writtenPitch: nil,
            midiNote: note.midiNote,
            velocityResolution: ScorePerformanceVelocityResolution(
                baseVelocity: Int(note.velocity),
                curveVelocity: nil,
                articulationDelta: 0,
                unclampedVelocity: Int(note.velocity),
                velocity: note.velocity
            ),
            staff: note.staff,
            voice: note.voice,
            handAssignment: note.handAssignment,
            fingeringText: note.fingeringText,
            timingProvenance: []
        )
    }
    return ScorePerformancePlan(
        id: ScorePerformancePlanID(rawValue: "test:\(identity.songID.uuidString):\(identity.scoreRevision)"),
        sourceScoreIdentity: ScorePerformanceSourceIdentity(
            songID: identity.songID,
            scoreRevision: identity.scoreRevision,
            logicalInstrumentID: scoreContext.logicalInstrument.id
        ),
        order: scoreContext.orderSelection,
        resolution: ScorePerformanceTickResolution(ticksPerQuarter: MusicXMLTempoMap.ticksPerQuarter),
        noteEvents: noteEvents,
        tempoEvents: tempoEvents,
        controllerEvents: controllerEvents,
        annotations: annotations,
        approximations: []
    )
}

func makeTestMusicXMLScore(notes: [TestScorePerformanceNote]) -> MusicXMLScore {
    MusicXMLScore(notes: notes.enumerated().map { ordinal, note in
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: note.staff,
                voice: note.voice,
                sourceOrdinal: ordinal
            ),
            partID: "P1",
            measureNumber: 1,
            tick: note.onTick,
            durationTicks: note.offTick - note.onTick,
            writtenPitch: nil,
            midiNote: note.midiNote,
            isRest: false,
            isChord: false,
            staff: note.staff,
            voice: note.voice,
            fingeringText: note.fingeringText
        )
    })
}
