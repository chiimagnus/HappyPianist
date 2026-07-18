import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func expressivityPipelineParsesAndPlumbsKeySignalsEndToEnd() throws {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0">
      <part-list>
        <score-part id="P1">
          <part-name>Piano</part-name>
        </score-part>
      </part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <key><fifths>-3</fifths><mode>minor</mode></key>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <staves>2</staves>
            <clef number="1"><sign>G</sign><line>2</line></clef>
            <clef number="2"><sign>F</sign><line>4</line></clef>
          </attributes>

          <direction placement="below">
            <direction-type><words>Ped.</words></direction-type>
            <staff>1</staff>
          </direction>

          <note>
            <pitch><step>C</step><octave>4</octave></pitch>
            <duration>1</duration>
            <voice>1</voice>
            <type>quarter</type>
            <staff>1</staff>
            <notations>
              <technical><fingering>1</fingering></technical>
              <fermata/>
              <arpeggiate/>
            </notations>
          </note>
          <note>
            <chord/>
            <pitch><step>E</step><octave>4</octave></pitch>
            <duration>1</duration>
            <voice>1</voice>
            <type>quarter</type>
            <staff>1</staff>
            <notations><arpeggiate/></notations>
          </note>

          <direction placement="below">
            <direction-type><words>*</words></direction-type>
            <staff>1</staff>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))

    #expect(score.keySignatureEvents.isEmpty == false)
    #expect(score.timeSignatureEvents.isEmpty == false)
    #expect(score.clefEvents.isEmpty == false)
    #expect(score.wordsEvents.isEmpty == false)
    #expect(score.fermataEvents.isEmpty == false)

    let expressivity = MusicXMLExpressivityOptions(
        fermataEnabled: true,
        arpeggiateEnabled: true,
        wordsSemanticsEnabled: true
    )

    let wordsSemantics = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: score.wordsEvents,
        tempoEvents: score.tempoEvents
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: score.pedalEvents + wordsSemantics.derivedPedalEvents)
    #expect(pedalTimeline.isDown(atTick: 0) == true)

    let attributeTimeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: score.timeSignatureEvents,
        keySignatureEvents: score.keySignatureEvents,
        clefEvents: score.clefEvents
    )
    #expect(attributeTimeline.timeSignature(atTick: 0)?.beats == 4)
    #expect(attributeTimeline.keySignature(atTick: 0)?.fifths == -3)
    #expect(attributeTimeline.clef(atTick: 0, staffNumber: 1)?.signToken == "G")
    #expect(attributeTimeline.clef(atTick: 0, staffNumber: 2)?.signToken == "F")

    let plan = makeTestScorePerformancePlan(from: score, expressivity: expressivity)
    let steps = PracticeStepBuilder().buildSteps(from: plan).steps
    #expect(steps.map(\.tick) == [0, 30])
    #expect(steps.flatMap(\.notes).map(\.midiNote) == [60, 64])
    #expect(steps[0].notes.first(where: { $0.midiNote == 60 })?.fingeringText == "1")

    let c4 = plan.noteEvents.first(where: { $0.midiNote == 60 })
    let e4 = plan.noteEvents.first(where: { $0.midiNote == 64 })
    #expect(c4?.performedOnTick == 0)
    #expect(e4?.performedOnTick == 30)
    #expect(c4?.performedOffTick == 480)
}

@Test
func performancePlanKeepsTempoControllersAndAnnotationsInCanonicalTickDomain() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <direction><sound tempo="120" damper-pedal="yes"/></direction>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
          <notations><fermata/><breath-mark/></notations>
        </note>
        <direction><direction-type><words>rit.</words></direction-type></direction>
        <direction><direction-type><pedal type="change"/></direction-type></direction>
        <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff></note>
        <direction><sound tempo="90"/></direction>
      </measure></part>
    </score-partwise>
    """
    var score = try MusicXMLParser().parse(data: Data(xml.utf8))
    for index in score.tempoEvents.indices {
        score.tempoEvents[index].performedOccurrenceIndex = 2
    }
    for index in score.pedalEvents.indices {
        score.pedalEvents[index].performedOccurrenceIndex = 2
    }
    for index in score.wordsEvents.indices {
        score.wordsEvents[index].performedOccurrenceIndex = 2
    }

    let words = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: score.wordsEvents,
        tempoEvents: score.tempoEvents
    )
    let tempoMap = MusicXMLTempoMap(
        tempoEvents: score.tempoEvents + words.derivedTempoEvents,
        tempoRamps: words.derivedTempoRamps,
        partID: "P1"
    )
    let pedalTimeline = MusicXMLPedalTimeline(events: score.pedalEvents + words.derivedPedalEvents)
    let expressivity = MusicXMLExpressivityOptions(
        wedgeEnabled: true,
        graceEnabled: true,
        fermataEnabled: true,
        arpeggiateEnabled: true,
        wordsSemanticsEnabled: true
    )
    let schedule = ScoreTimingScheduleBuilder().build(
        notes: score.notes,
        performanceTimingEnabled: true,
        graceEnabled: expressivity.graceEnabled,
        arpeggiateEnabled: expressivity.arpeggiateEnabled
    )
    let fermataTimeline = MusicXMLFermataTimeline(
        fermataEvents: score.fermataEvents,
        notes: score.notes
    )
    let logicalInstrument = MusicXMLLogicalInstrument(
        id: "piano:P1",
        memberPartIDs: ["P1"],
        classification: .piano,
        evidence: []
    )
    let songID = try #require(UUID(uuidString: "50C583D1-343A-4577-BF5F-9003314A5051"))
    let plan = ScorePerformancePlanBuilder().build(
        sourceIdentity: ScorePerformanceSourceIdentity(
            songID: songID,
            scoreRevision: "revision",
            logicalInstrumentID: logicalInstrument.id
        ),
        order: MusicXMLOrderSelection(requested: .performed, applied: .performed),
        logicalInstrument: logicalInstrument,
        notes: score.notes,
        timingSchedule: schedule,
        velocityResolver: MusicXMLVelocityResolver(
            dynamicEvents: score.dynamicEvents,
            wedgeEvents: score.wedgeEvents,
            wedgeEnabled: expressivity.wedgeEnabled
        ),
        expressivity: expressivity,
        handAssignments: [:],
        tempoMap: tempoMap,
        pedalTimeline: pedalTimeline,
        tempoAnnotations: words.tempoAnnotations,
        fermataEvents: score.fermataEvents,
        fermataTimeline: fermataTimeline
    )

    #expect(plan.tempoEvents.map(\.tick) == [0, 480, 960])
    #expect(plan.tempoEvents.map(\.performedOccurrenceIndex) == [2, 2, 2])
    #expect(plan.tempoEvents.first(where: { $0.endTick != nil })?.endTick == 960)
    #expect(plan.tempoEvents.first(where: { $0.endTick != nil })?.endQuarterBPM == 90)
    #expect(plan.controllerEvents.map(\.value) == [127, 0, 127])
    #expect(plan.controllerEvents.allSatisfy { $0.controllerNumber == 64 })
    #expect(plan.controllerEvents.allSatisfy { $0.performedOccurrenceIndex == 2 })
    #expect(plan.annotations.contains { $0.kind == .phrase && $0.tick == 420 })
    #expect(plan.annotations.contains { $0.kind == .pause && $0.text == "fermata" && $0.tick == 420 })
    #expect(plan.annotations.contains {
        $0.kind == .tempoWord && $0.tick == 480 && $0.performedOccurrenceIndex == 2
    })
}

@Test
func musicXMLScoreSnapshotCapturesSourceFactsWithoutHeuristics() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <direction><direction-type><dynamics><mf/></dynamics></direction-type></direction>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let snapshot = MusicXMLScoreSnapshot().encode(score)
    let noteID = try #require(score.notes.first?.sourceID)
    let directionID = try #require(score.dynamicEvents.first?.sourceID)

    #expect(snapshot.contains("kind=note|sourceNoteID=\(noteID.description)|sourceIndex=0|part=P1"))
    #expect(snapshot.contains("kind=dynamic|sourceDirectionID=\(directionID.description)"))
    #expect(snapshot.contains("kind=measure|sourceMeasureID=P1:1:1"))
}

@Test
func musicXMLScoreSnapshotIsIndependentOfFactArrayOrder() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time></attributes>
          <barline location="left"><repeat direction="forward"/><ending number="1" type="start"/></barline>
          <direction>
            <direction-type><dynamics><p/></dynamics><wedge type="crescendo"/><words>dolce</words><fermata/></direction-type>
            <sound tempo="80" damper-pedal="yes" segno="s1"/>
          </direction>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
        </measure>
        <measure number="2">
          <attributes><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
          <direction>
            <direction-type><dynamics><f/></dynamics><wedge type="stop"/><words>cantabile</words><fermata/></direction-type>
            <sound tempo="100" damper-pedal="no" coda="c1"/>
          </direction>
          <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
          <barline location="right"><ending number="1" type="stop"/><repeat direction="backward"/></barline>
        </measure>
      </part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    var reordered = score
    reordered.notes.reverse()
    reordered.tempoEvents.reverse()
    reordered.soundDirectives.reverse()
    reordered.pedalEvents.reverse()
    reordered.dynamicEvents.reverse()
    reordered.wedgeEvents.reverse()
    reordered.fermataEvents.reverse()
    reordered.timeSignatureEvents.reverse()
    reordered.wordsEvents.reverse()
    reordered.measures.reverse()
    reordered.repeatDirectives.reverse()
    reordered.endingDirectives.reverse()

    #expect(MusicXMLScoreSnapshot().encode(reordered) == MusicXMLScoreSnapshot().encode(score))
}

@Test
func parserAssignsStableDirectionIdentityAcrossEventKinds() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes>
        <direction>
          <direction-type><dynamics><mf/></dynamics><wedge type="crescendo" number="1"/></direction-type>
          <sound tempo="90" damper-pedal="yes" segno="s1"/>
        </direction>
        <direction><direction-type><words>dolce</words></direction-type></direction>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """

    let scoreA = try MusicXMLParser().parse(data: Data(xml.utf8))
    let scoreB = try MusicXMLParser().parse(data: Data(xml.utf8))
    let sharedID = try #require(scoreA.dynamicEvents.first?.sourceID)

    #expect(scoreA.dynamicEvents.map(\.sourceID) == scoreB.dynamicEvents.map(\.sourceID))
    #expect(scoreA.wedgeEvents.first?.sourceID == sharedID)
    #expect(scoreA.tempoEvents.first?.sourceID == sharedID)
    #expect(scoreA.pedalEvents.first?.sourceID == sharedID)
    #expect(scoreA.soundDirectives.first?.sourceID == sharedID)
    #expect(scoreA.wordsEvents.first?.sourceID != sharedID)
}


@Test
func pedalChangePreservesBothControllerEdgesUnderOneDirectionSource() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes>
        <direction><direction-type><pedal type="change"/></direction-type></direction>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """

    let events = try MusicXMLParser().parse(data: Data(xml.utf8)).pedalEvents
    #expect(events.count == 2)
    #expect(events.map(\.isDown) == [false, true])
    #expect(events[0].sourceID != nil)
    #expect(events[0].sourceID == events[1].sourceID)
}

@Test
func dynamicCurvePreservesBaseAndAppliesAccentAfterInterpolation() {
    let scope = MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
    let resolver = MusicXMLVelocityResolver(
        dynamicEvents: [
            MusicXMLDynamicEvent(tick: 0, velocity: 60, scope: scope, source: .directionDynamics),
            MusicXMLDynamicEvent(tick: 960, velocity: 100, scope: scope, source: .directionDynamics),
        ],
        wedgeEvents: [
            MusicXMLWedgeEvent(tick: 0, kind: .crescendoStart, numberToken: "1", scope: scope),
            MusicXMLWedgeEvent(tick: 960, kind: .stop, numberToken: "1", scope: scope),
        ],
        wedgeEnabled: true
    )
    let note = MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 2,
        tick: 480,
        durationTicks: 480,
        midiNote: 60,
        isRest: false,
        isChord: false,
        tieStart: false,
        tieStop: false,
        staff: 1,
        voice: 1,
        articulations: [.accent]
    )

    let resolution = resolver.resolution(for: note)

    #expect(resolution.baseVelocity == 60)
    #expect(resolution.curveVelocity == 80)
    #expect(resolution.articulationDelta == 10)
    #expect(resolution.unclampedVelocity == 90)
    #expect(resolution.velocity == 90)
    #expect(resolution.curve?.numberToken == "1")
}

@Test
func dynamicCurveKeepsNestedNumbersIndependentAndDiagnosesMissingTargets() {
    let scope = MusicXMLEventScope(partID: "P1", staff: 1, voice: nil)
    let resolver = MusicXMLVelocityResolver(
        dynamicEvents: [
            MusicXMLDynamicEvent(tick: 0, velocity: 60, scope: scope, source: .directionDynamics),
            MusicXMLDynamicEvent(tick: 480, velocity: 90, scope: scope, source: .directionDynamics),
        ],
        wedgeEvents: [
            MusicXMLWedgeEvent(tick: 0, kind: .crescendoStart, numberToken: "1", scope: scope),
            MusicXMLWedgeEvent(tick: 0, kind: .diminuendoStart, numberToken: "2", scope: scope),
            MusicXMLWedgeEvent(tick: 0, kind: .stop, numberToken: "2", scope: scope),
            MusicXMLWedgeEvent(tick: 480, kind: .stop, numberToken: "1", scope: scope),
            MusicXMLWedgeEvent(tick: 720, kind: .crescendoStart, numberToken: "3", scope: scope),
            MusicXMLWedgeEvent(tick: 960, kind: .stop, numberToken: "3", scope: scope),
        ],
        wedgeEnabled: true
    )

    #expect(resolver.dynamicCurves.map(\.numberToken) == ["1"])
    #expect(resolver.wedgeApproximations.map(\.reason).sorted() == [
        "wedge-missing-target-dynamic",
        "wedge-zero-duration",
    ])
}

@Test
func velocityResolutionClampsAfterKeepingUnclampedArticulationResult() {
    let resolver = MusicXMLVelocityResolver(dynamicEvents: [], defaultVelocity: 125)
    let note = MusicXMLNoteEvent(
        partID: "P1",
        measureNumber: 1,
        tick: 0,
        durationTicks: 480,
        midiNote: 60,
        isRest: false,
        isChord: false,
        tieStart: false,
        tieStop: false,
        staff: 1,
        voice: 1,
        articulations: [.marcato]
    )

    let resolution = resolver.resolution(for: note)
    #expect(resolution.baseVelocity == 125)
    #expect(resolution.unclampedVelocity == 140)
    #expect(resolution.velocity == 127)
}

@Test
func ornamentSchedulerGeneratesOnlyFromExplicitPerformanceFacts() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
          <notations><ornaments><trill-mark/><accidental-mark placement="above">natural</accidental-mark></ornaments></notations>
        </note>
        <note>
          <pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
          <notations><ornaments><trill-mark/></ornaments></notations>
        </note>
        <note>
          <pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
          <notations><ornaments><tremolo type="single">3</tremolo></ornaments></notations>
        </note>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
          <notations><glissando type="start" number="1"/></notations>
        </note>
        <note>
          <pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice><staff>1</staff>
          <notations><glissando type="stop" number="1"/></notations>
        </note>
      </measure></part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let schedule = ScoreTimingScheduleBuilder().build(
        notes: score.notes,
        performanceTimingEnabled: true
    )

    let trillNotes = schedule.generatedNotes.filter { $0.notationKind == .trillMark }
    #expect(trillNotes.map(\.midiNote) == [60, 62, 60, 62, 60, 62, 60, 62, 60])
    #expect(trillNotes.allSatisfy { $0.sourceNoteIndices == [0] })

    let unsupportedTrill = try #require(schedule.notationResolutions.first {
        $0.notationKind == .trillMark && $0.sourceNoteIndices == [1]
    })
    #expect(unsupportedTrill.status == .unsupported(reason: "ornament-accidental-unavailable"))

    let tremoloNotes = schedule.generatedNotes.filter { $0.notationKind == .tremolo }
    #expect(tremoloNotes.count == 8)
    #expect(tremoloNotes.allSatisfy { $0.midiNote == 67 })

    let glissandoNotes = schedule.generatedNotes.filter { $0.notationKind == .glissando }
    #expect(glissandoNotes.map(\.midiNote) == Array(60..<72))
    #expect(glissandoNotes.first?.onTick == 1_440)
    #expect(glissandoNotes.last?.offTick == 1_920)
}


@Test
func expressivePianoFixtureLocksSourceNotationTimingAndProvenance() throws {
    let fixture = try PianoPerformanceFixtureLoader().fixture(id: "expressive-piano-semantics")
    let score = try MusicXMLParser().parse(fileURL: fixture.url)
    let schedule = ScoreTimingScheduleBuilder().build(
        notes: score.notes,
        performanceTimingEnabled: true,
        graceEnabled: true,
        logicalInstruments: score.logicalInstruments,
        arpeggiateEnabled: true
    )

    expectSnapshot(
        expressivePianoSemanticsSnapshot(score: score, schedule: schedule),
        equals: """
notation|note=1|source=P1:1:1:1:1:1:notation:0|kind=slur|type=start|number=1|placement=null|text=null
notation|note=4|source=P1:1:1:1:1:4:notation:0|kind=slur|type=stop|number=1|placement=null|text=null
notation|note=4|source=P1:1:1:1:1:4:notation:1|kind=breath-mark|type=null|number=null|placement=null|text=null
notation|note=6|source=P1:2:2:1:1:0:notation:0|kind=trill-mark|type=null|number=null|placement=null|text=null
notation|note=6|source=P1:2:2:1:1:0:notation:1|kind=accidental-mark|type=null|number=null|placement=above|text=natural
notation|note=7|source=P1:2:2:1:1:1:notation:0|kind=trill-mark|type=null|number=null|placement=null|text=null
notation|note=8|source=P1:2:2:1:1:2:notation:0|kind=tremolo|type=single|number=null|placement=null|text=3
notation|note=9|source=P1:2:2:1:1:3:notation:0|kind=glissando|type=start|number=1|placement=null|text=null
notation|note=10|source=P1:3:3:1:1:0:notation:0|kind=glissando|type=stop|number=1|placement=null|text=null
notation|note=11|source=P1:3:3:1:1:1:notation:0|kind=schleifer|type=null|number=null|placement=null|text=null
timing|note=0|source=P1:1:1:1:1:0|written=0-0|performed=0-120|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=1|source=P1:1:1:1:1:1|written=0-480|performed=120-135|policy=slurLegato|provenance=score,grace:makeTime,notation:slur:P1:1:1:1:1:1:notation:0:generic-score-v1
timing|note=2|source=P1:1:1:1:1:2|written=0-480|performed=135-150|policy=slurLegato|provenance=score,grace:makeTime,arpeggio:1:up,notation:slur:P1:1:1:1:1:1:notation:0:generic-score-v1
timing|note=3|source=P1:1:1:1:1:3|written=0-480|performed=150-600|policy=slurLegato|provenance=score,grace:makeTime,arpeggio:1:up,notation:slur:P1:1:1:1:1:1:notation:0:generic-score-v1
timing|note=4|source=P1:1:1:1:1:4|written=480-960|performed=600-1020|policy=breathGap|provenance=score,grace:makeTime,notation:breath-mark:P1:1:1:1:1:4:notation:1:generic-score-v1
timing|note=5|source=P1:1:1:1:1:5|written=960-1920|performed=1080-2040|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=6|source=P1:2:2:1:1:0|written=1920-2400|performed=2040-2520|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=7|source=P1:2:2:1:1:1|written=2400-2880|performed=2520-3000|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=8|source=P1:2:2:1:1:2|written=2880-3360|performed=3000-3480|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=9|source=P1:2:2:1:1:3|written=3360-3840|performed=3480-3960|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=10|source=P1:3:3:1:1:0|written=3840-4320|performed=3960-4440|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=11|source=P1:3:3:1:1:1|written=4320-4800|performed=4440-4920|policy=graceMakeTime|provenance=score,grace:makeTime
timing|note=12|source=P1:3:3:1:1:2|written=4800-5760|performed=4920-5880|policy=graceMakeTime|provenance=score,grace:makeTime
generated|kind=trill-mark|count=9|pitches=72,74,72,74,72,74,72,74,72|ticks=2040-2520|profile=generic-score-v1
generated|kind=tremolo|count=8|pitches=67,67,67,67,67,67,67,67|ticks=3000-3480|profile=generic-score-v1
generated|kind=glissando|count=12|pitches=60,61,62,63,64,65,66,67,68,69,70,71|ticks=3480-3960|profile=generic-score-v1
resolution|source=P1:2:2:1:1:0:notation:0|kind=trill-mark|notes=6|replaces=6|status=generated
resolution|source=P1:2:2:1:1:1:notation:0|kind=trill-mark|notes=7|replaces=|status=unsupported:ornament-accidental-unavailable
resolution|source=P1:2:2:1:1:2:notation:0|kind=tremolo|notes=8|replaces=8|status=generated
resolution|source=P1:2:2:1:1:3:notation:0|kind=glissando|notes=9,10|replaces=9|status=generated
resolution|source=P1:3:3:1:1:0:notation:0|kind=glissando|notes=9,10|replaces=|status=generated
dynamic|ticks=0-480|velocity=50-90|number=1
tempo-ramp|ticks=1920-3840|bpm=120-90
unsupported|kind=schleifer|count=1
"""
    )
}

private func expressivePianoSemanticsSnapshot(
    score: MusicXMLScore,
    schedule: ScoreTimingSchedule
) -> String {
    var lines: [String] = []
    for (noteIndex, note) in score.notes.enumerated() {
        for notation in note.performanceNotations {
            lines.append(
                "notation|note=\(noteIndex)|source=\(notation.sourceID?.description ?? "unresolved")"
                    + "|kind=\(notation.diagnosticKindToken)|type=\(notation.typeToken ?? "null")"
                    + "|number=\(notation.numberToken ?? "null")|placement=\(notation.placementToken ?? "null")"
                    + "|text=\(notation.textToken ?? "null")"
            )
        }
    }
    for entry in schedule.entries {
        lines.append(
            "timing|note=\(entry.noteIndex)|source=\(entry.sourceNoteID?.description ?? "unresolved")"
                + "|written=\(entry.writtenOnTick)-\(entry.writtenOffTick)"
                + "|performed=\(entry.performedOnTick)-\(entry.performedOffTick)"
                + "|policy=\(entry.releasePolicy.rawValue)"
                + "|provenance=\(entry.provenance.map(expressiveProvenanceToken).joined(separator: ","))"
        )
    }
    for kind in [MusicXMLPerformanceNotationKind.trillMark, .tremolo, .glissando] {
        let events = schedule.generatedNotes.filter { $0.notationKind == kind }
        guard let first = events.first, let last = events.last else { continue }
        lines.append(
            "generated|kind=\(kind.rawValue)|count=\(events.count)"
                + "|pitches=\(events.map { String($0.midiNote) }.joined(separator: ","))"
                + "|ticks=\(first.onTick)-\(last.offTick)|profile=\(first.interpretationProfileID)"
        )
    }
    for resolution in schedule.notationResolutions {
        lines.append(
            "resolution|source=\(resolution.sourceNotationID?.description ?? "unresolved")"
                + "|kind=\(resolution.notationKind.rawValue)"
                + "|notes=\(resolution.sourceNoteIndices.map(String.init).joined(separator: ","))"
                + "|replaces=\(resolution.replacesSourceNoteIndices.map(String.init).joined(separator: ","))"
                + "|status=\(expressiveResolutionStatusToken(resolution.status))"
        )
    }
    let velocityResolver = MusicXMLVelocityResolver(
        dynamicEvents: score.dynamicEvents,
        wedgeEvents: score.wedgeEvents,
        wedgeEnabled: true
    )
    for curve in velocityResolver.dynamicCurves {
        lines.append(
            "dynamic|ticks=\(curve.startTick)-\(curve.endTick)"
                + "|velocity=\(curve.startVelocity)-\(curve.endVelocity)|number=\(curve.numberToken)"
        )
    }
    let words = MusicXMLWordsSemanticsInterpreter().interpret(
        wordsEvents: score.wordsEvents,
        tempoEvents: score.tempoEvents
    )
    for ramp in words.derivedTempoRamps {
        lines.append(
            "tempo-ramp|ticks=\(ramp.startTick)-\(ramp.endTick)"
                + "|bpm=\(Int(ramp.startQuarterBPM))-\(Int(ramp.endQuarterBPM))"
        )
    }
    for (kind, count) in score.unsupportedPerformanceNotationCountsByKind.sorted(by: { $0.key < $1.key }) {
        lines.append("unsupported|kind=\(kind)|count=\(count)")
    }
    return lines.joined(separator: "\n") + "\n"
}

private func expressiveProvenanceToken(_ provenance: ScoreTimingProvenance) -> String {
    switch provenance {
    case .score:
        "score"
    case .performanceOffset:
        "performance-offset"
    case let .grace(kind):
        "grace:\(kind.rawValue)"
    case let .arpeggio(numberToken, direction):
        "arpeggio:\(numberToken):\(direction.rawValue)"
    case let .interpretationProfile(id):
        "profile:\(id)"
    case let .performanceNotation(kind, sourceID, profileID):
        "notation:\(kind.rawValue):\(sourceID?.description ?? "unresolved"):\(profileID)"
    case let .approximation(reason):
        "approximation:\(reason)"
    }
}

private func expressiveResolutionStatusToken(_ status: ScorePerformanceNotationResolutionStatus) -> String {
    switch status {
    case .generated:
        "generated"
    case let .unsupported(reason):
        "unsupported:\(reason)"
    }
}
