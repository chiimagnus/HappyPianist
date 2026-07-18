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

    let steps = PracticeStepBuilder().buildSteps(from: score, expressivity: expressivity).steps
    #expect(steps.count == 1)
    #expect(steps[0].notes.map(\.midiNote) == [60, 64])
    #expect(steps[0].notes.first(where: { $0.midiNote == 60 })?.fingeringText == "1")

    let fermataTimeline = MusicXMLFermataTimeline(fermataEvents: score.fermataEvents, notes: score.notes)
    let spans = MusicXMLNoteSpanBuilder().buildSpans(
        from: score.notes,
        expressivity: expressivity
    )
    let c4Span = spans.first(where: { $0.midiNote == 60 })
    let e4Span = spans.first(where: { $0.midiNote == 64 })
    #expect(c4Span?.onTick == 0)
    #expect(e4Span?.onTick == 30)
    #expect(c4Span?.offTick == 480)
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

    #expect(snapshot.contains("kind=note|sourceNoteID=unresolved|sourceIndex=0|part=P1"))
    #expect(snapshot.contains("kind=dynamic|sourceDirectionID=unresolved"))
    #expect(snapshot.contains("kind=measure|sourceMeasureID=P1-m1"))
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
