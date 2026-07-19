import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func layoutAssignsItemsToTrebleAndBassStaves() {
    let score = notationProjectionScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    #expect(layout.items.count == 2)
    #expect(Set(layout.items.map(\.staffNumber)) == [1, 2])
}

@Test
func layoutPositionsWrittenPitchUsingTheActiveClef() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
        <attributes><clef><sign>F</sign><line>4</line></clef></attributes>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(projection.sourceNotes.map { $0.clef?.signToken } == ["G", "F"])
    #expect(layout.items.map(\.staffStep) == [-2, 10])
    #expect(layout.attributeChanges.first?.clefGlyphToken == .fClef)
}

@Test
func layoutOmitsPitchedNotesMarkedPrintObjectNo() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <note print-object="no"><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
        <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(projection.sourceNotes.map(\.isPrintObjectVisible) == [false, true])
    #expect(layout.items.count == 1)
    #expect(layout.items.first?.occurrenceID == projection.performedOccurrences[1].id.description)
}

@Test
func layoutRendersWholeMeasureRestWithoutTypeAtMeasureCenter() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes>
          <divisions>1</divisions>
          <time><beats>4</beats><beat-type>4</beat-type></time>
          <clef><sign>G</sign><line>2</line></clef>
        </attributes>
        <note><rest measure="yes"/><duration>4</duration><staff>1</staff><voice>1</voice></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        measureSpans: score.measures,
        viewportWidthStaffSpaces: 36,
        scrollTick: 0
    )
    let rest = try #require(layout.rests.first)

    #expect(projection.fallbacks.isEmpty)
    #expect(rest.noteValue == .whole)
    #expect(rest.isMeasureRest)
    #expect(rest.glyphToken == .restWhole)
    #expect(rest.xPosition > 0.5)
}

@Test
func layoutSupportsSixtyFourthAndOneHundredTwentyEighthNotesAndRests() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>32</divisions><clef><sign>G</sign><line>2</line></clef></attributes>
        <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><type>64th</type></note>
        <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><type>128th</type></note>
        <note><rest/><duration>2</duration><type>64th</type></note>
        <note><rest/><duration>1</duration><type>128th</type></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(projection.fallbacks.isEmpty)
    #expect(layout.items.map(\.noteValue) == [.sixtyFourth, .oneHundredTwentyEighth])
    #expect(layout.items.map(\.flagGlyphToken) == [.flagSixtyFourthDown, .flagOneHundredTwentyEighthDown])
    #expect(layout.rests.map(\.noteValue) == [.sixtyFourth, .oneHundredTwentyEighth])
    #expect(layout.rests.compactMap(\.glyphToken) == [.restSixtyFourth, .restOneHundredTwentyEighth])
}

@Test
func layoutEmitsBarlinesForMeasureSpansStartAndEndTicks() {
    let measureSpans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 2, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]

    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: .empty,
        measureSpans: measureSpans
    )

    #expect(layout.barlines.map(\.tick) == [480, 960])
}

@Test
func commonPianoMarksKeepSourcePlacementAndUseCollisionAwareLayout() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes>
            <divisions>1</divisions>
            <key><fifths>0</fifths></key>
            <time><beats>4</beats><beat-type>4</beat-type></time>
            <staves>2</staves>
            <clef number="1"><sign>G</sign><line>2</line></clef>
            <clef number="2"><sign>F</sign><line>4</line></clef>
          </attributes>
          <direction placement="below">
            <direction-type><dynamics><ff/></dynamics></direction-type><staff>2</staff>
          </direction>
          <direction placement="above">
            <direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>88</per-minute></metronome></direction-type>
            <staff>1</staff>
          </direction>
          <direction placement="below">
            <direction-type><pedal type="start"/></direction-type><staff>2</staff>
          </direction>
          <note>
            <pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type>
            <voice>1</voice><staff>1</staff>
            <notations>
              <articulations><accent/></articulations>
              <fermata placement="below"/>
              <technical><fingering placement="above">3</fingering></technical>
              <arpeggiate direction="up"/>
            </notations>
          </note>
          <barline location="right"><ending number="1" type="start"/><repeat direction="backward" times="2"/></barline>
        </measure>
        <measure number="2">
          <attributes>
            <key><fifths>2</fifths></key>
            <time><beats>3</beats><beat-type>4</beat-type></time>
            <clef number="2"><sign>G</sign><line>2</line></clef>
          </attributes>
          <direction placement="above"><direction-type><words>dolce</words></direction-type><staff>1</staff></direction>
          <note>
            <pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type>
            <voice>1</voice><staff>1</staff>
          </note>
          <barline location="right"><ending number="1" type="stop"/><repeat direction="forward"/></barline>
        </measure>
      </part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        measureSpans: score.measures,
        viewportWidthStaffSpaces: 60,
        scrollTick: 240
    )

    let dynamic = try #require(projection.marks.first { $0.kind == .dynamic })
    let tempo = try #require(projection.marks.first { $0.kind == .tempo })
    let pedal = try #require(projection.marks.first { $0.kind == .pedalStart })
    #expect(dynamic.text == "ff")
    #expect(dynamic.staff == 2)
    #expect(dynamic.placementToken == "below")
    #expect(tempo.staff == 1)
    #expect(tempo.placementToken == "above")
    #expect(tempo.text == "♩ = 88")
    #expect(pedal.staff == 2)
    #expect(pedal.placementToken == "below")

    #expect(projection.attributeChanges.map(\.tick) == [480, 480])
    #expect(projection.attributeChanges.first { $0.staff == 1 }?.keySignatureFifths == 2)
    #expect(projection.attributeChanges.first { $0.staff == 2 }?.clef?.signToken == "G")
    #expect(layout.attributeChanges.count == 2)
    #expect(layout.attributeChanges.allSatisfy { $0.xPosition != layout.items.last?.xPosition })

    #expect(layout.marks.contains { $0.kind == .articulation(.articulationAccentAbove) })
    #expect(layout.marks.contains { $0.kind == .arpeggio(.arpeggiatoUp) })
    #expect(layout.marks.contains { $0.kind == .fingering && $0.text == "3" && $0.placement == .above })
    #expect(layout.marks.contains { $0.kind == .fermata && $0.placement == .below })
    #expect(layout.marks.contains { $0.kind == .repeatBackward })
    #expect(layout.marks.contains { $0.kind == .repeatForward })
    #expect(layout.marks.contains { $0.kind == .endingStart && $0.text == "1" })
    #expect(layout.marks.contains { $0.kind == .endingStop })

    let collidingBelowMarks = layout.marks.filter {
        $0.tick == 0 && $0.staffNumber == 2 && $0.placement == .below
    }
    #expect(Set(collidingBelowMarks.map(\.collisionLevel)).count == collidingBelowMarks.count)

    var performedScore = score
    let sourceFirstMeasure = try #require(score.measures.first)
    performedScore.measures.append(MusicXMLMeasureSpan(
        partID: sourceFirstMeasure.partID,
        measureNumber: 3,
        sourceMeasureIndex: sourceFirstMeasure.sourceMeasureIndex,
        sourceMeasureNumberToken: sourceFirstMeasure.sourceMeasureNumberToken,
        occurrenceIndex: 7,
        startTick: 960,
        endTick: 1_440
    ))
    performedScore.repeatDirectives = []
    performedScore.endingDirectives = []
    let repeatedProjection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score,
        performedScore: performedScore
    )
    #expect(repeatedProjection.marks.filter { $0.kind == .repeatBackward }.map(\.tick) == [480, 1_440])
    #expect(repeatedProjection.marks.filter { $0.kind == .endingStart }.map(\.tick) == [0, 960])
}

@Test
func projectionDoesNotRenderPlaybackOnlySoundTempoOrDynamics() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <direction><sound tempo="72" dynamics="80"/></direction>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )

    #expect(score.tempoEvents.map(\.quarterBPM) == [72])
    #expect(score.dynamicEvents.count == 1)
    #expect(projection.marks.contains { $0.kind == .tempo } == false)
    #expect(projection.marks.contains { $0.kind == .dynamic } == false)
}

@Test
func projectionKeepsMetronomeSpellingWhenSoundOverridesPlaybackTempo() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <direction placement="above">
          <direction-type>
            <metronome><beat-unit>eighth</beat-unit><beat-unit-dot/><per-minute>80</per-minute></metronome>
          </direction-type>
          <sound tempo="60"/>
        </direction>
        <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let event = try #require(score.tempoEvents.first)
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let mark = try #require(projection.marks.first { $0.kind == .tempo })

    #expect(score.tempoEvents.count == 1)
    #expect(event.quarterBPM == 60)
    #expect(event.notationBeatUnitToken == "eighth")
    #expect(event.notationBeatUnitDotCount == 1)
    #expect(event.notationPerMinute == 80)
    #expect(mark.text == "♪. = 80")
    #expect(mark.placementToken == "above")
}

@Test
func notationProjectionKeepsSourceFactsAndOccurrenceLinksWhileOverlayStaysTransient() throws {
    let score = notationProjectionScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let activeEvent = try #require(plan.noteEvents.first)

    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let overlay = ScoreNotationProjection.Overlay(
        activeEventIDs: [activeEvent.id],
        activeTickRange: 0 ..< 960
    )

    #expect(projection.sourceNotes.count == 2)
    #expect(projection.sourceNotes.map(\.id) == score.notes.compactMap(\.sourceID))
    #expect(projection.sourceNotes.map(\.staff) == score.notes.map { $0.staff ?? 1 })
    #expect(projection.sourceNotes.map(\.voice) == score.notes.map { $0.voice ?? 1 })
    #expect(projection.performedOccurrences.count == 2)
    #expect(projection.performedOccurrences[0].sourceNoteID == projection.sourceNotes[0].id)
    #expect(projection.performedOccurrences[0].performanceEventIDs == [activeEvent.id])
    #expect(overlay.activeEventIDs == [activeEvent.id])
    #expect(overlay.activeTickRange == 0 ..< 960)
    #expect(GrandStaffNotationLayoutService().makeLayout(projection: projection, overlay: overlay).items.count == 1)
}

@Test
func projectionLayoutUsesWrittenDurationAndAccidentalInsteadOfPerformanceOrMidi() throws {
    let score = notationProjectionScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let activeEvent = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)

    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: [activeEvent.id], activeTickRange: nil)
    )
    let flat = try #require(layout.items.first { $0.tick == 0 })
    let sharp = try #require(layout.items.first { $0.tick == 960 })

    #expect(activeEvent.performedOffTick - activeEvent.performedOnTick == 480)
    #expect(flat.durationTicks == 960)
    #expect(flat.noteValue == .half)
    #expect(flat.displayedAccidental?.kind == .flat)
    #expect(flat.isHighlighted)
    #expect(sharp.displayedAccidental?.kind == .sharp)
    #expect(sharp.isHighlighted == false)
    #expect(flat.staffStep == -1)
    #expect(sharp.staffStep == 10)
}

@Test
func projectionResolvesKeyAndMeasureAccidentalStateWithoutLosingPitchTransforms() throws {
    let score = accidentalStateScore()
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(layout.items.map { $0.displayedAccidental?.kind } == [
        nil,
        .natural,
        nil,
        .sharp,
        .natural,
        .unsupported,
    ])
    #expect(projection.sourceNotes.allSatisfy { $0.keySignature?.fifths == 1 })
    #expect(projection.sourceNotes.first?.transpose == .init(
        diatonic: -1,
        chromatic: -2,
        octaveChange: 0,
        isDouble: false
    ))
    #expect(projection.sourceNotes.first?.octaveShifts == [
        .init(kind: .up, size: 8, numberToken: "1"),
    ])
    #expect(layout.items.last?.displayedAccidental?.sourceToken == "quarter-sharp")
    #expect(layout.items.last?.displayedAccidental?.alter == 0.5)
}

@Test
func projectionLayoutKeepsEveryWrittenTieContributor() throws {
    let score = notationTieScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let event = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)

    #expect(plan.noteEvents.count == 1)
    #expect(projection.performedOccurrences.count == 2)
    #expect(projection.performedOccurrences.allSatisfy { $0.performanceEventIDs == [event.id] })

    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: [event.id], activeTickRange: nil)
    )
    let items = layout.items
    #expect(items.map(\.tick) == [0, 480])
    #expect(items.allSatisfy { $0.isHighlighted })
    let tie = try #require(layout.ties.first)
    #expect(layout.ties.count == 1)
    #expect(tie.startOccurrenceID == items[0].occurrenceID)
    #expect(tie.endOccurrenceID == items[1].occurrenceID)
    #expect(tie.continuesFromPrevious == false)
    #expect(tie.continuesToNext == false)
}

@Test
func layoutKeepsTieContinuationAcrossActiveRangeAndViewportBoundary() throws {
    let score = notationTieScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        ),
        overlay: .init(activeEventIDs: [], activeTickRange: 240 ..< 960),
        viewportWidthStaffSpaces: 2,
        scrollTick: 480
    )

    let tie = try #require(layout.ties.first)
    #expect(tie.continuesFromPrevious)
    #expect(tie.continuesToNext == false)
    #expect(tie.startOccurrenceID == nil)
    #expect(tie.endOccurrenceID == layout.items.first?.occurrenceID)
}

@Test
func projectionAndLayoutKeepVisibleRestsSameNumberSlursAndNestedTuplets() throws {
    let score = notationRestAndSpannerScore()
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)

    #expect(projection.sourceNotes.filter(\.isRest).map(\.isPrintObjectVisible) == [true, false])
    let rest = try #require(layout.rests.first)
    #expect(layout.rests.count == 1)
    #expect(rest.staffNumber == 2)
    #expect(rest.voice == 2)
    #expect(rest.noteValue == .quarter)
    #expect(rest.dotCount == 1)

    #expect(layout.slurs.map(\.numberToken) == ["2", "2"])
    #expect(layout.slurs.map(\.placementToken) == ["above", "below"])
    #expect(layout.slurs.allSatisfy { !$0.continuesFromPrevious && !$0.continuesToNext })
    #expect(layout.tuplets.map(\.numberToken) == ["1", "2"])
    #expect(layout.tuplets.map(\.displayNumber) == [3, 3])
    #expect(layout.tuplets.map(\.bracketToken) == ["yes", "no"])
    #expect(layout.tuplets.map(\.nestingLevel) == [0, 1])
    #expect(layout.tuplets.allSatisfy { $0.startOccurrenceID != nil && $0.endOccurrenceID != nil })
}

@Test
func layoutPairsTieSlurAndTupletAcrossGrandStaffStaves() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes>
          <divisions>1</divisions><staves>2</staves>
          <clef number="1"><sign>G</sign><line>2</line></clef>
          <clef number="2"><sign>F</sign><line>4</line></clef>
        </attributes>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type>
          <voice>1</voice><staff>1</staff>
          <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
          <notations>
            <tied type="start" number="1"/><slur type="start" number="1"/>
            <tuplet type="start" number="1" bracket="yes"/>
          </notations>
        </note>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type>
          <voice>1</voice><staff>2</staff>
          <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
          <notations>
            <tied type="stop" number="1"/><slur type="stop" number="1"/>
            <tuplet type="stop" number="1"/>
          </notations>
        </note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    #expect(layout.items.map(\.staffNumber) == [1, 2])
    #expect(layout.ties.count == 1)
    #expect(layout.slurs.count == 1)
    #expect(layout.tuplets.count == 1)
    #expect(layout.ties[0].startOccurrenceID != nil && layout.ties[0].endOccurrenceID != nil)
    #expect(layout.slurs[0].startOccurrenceID != nil && layout.slurs[0].endOccurrenceID != nil)
    #expect(layout.tuplets[0].startOccurrenceID != nil && layout.tuplets[0].endOccurrenceID != nil)
}

@Test
func layoutUsesOneArpeggioMarkAcrossGrandStaffStaves() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes>
          <divisions>1</divisions><staves>2</staves>
          <clef number="1"><sign>G</sign><line>2</line></clef>
          <clef number="2"><sign>F</sign><line>4</line></clef>
        </attributes>
        <note>
          <pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type>
          <voice>1</voice><staff>1</staff><notations><arpeggiate number="1" direction="up"/></notations>
        </note>
        <note>
          <chord/><pitch><step>E</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type>
          <voice>1</voice><staff>2</staff><notations><arpeggiate number="1" direction="up"/></notations>
        </note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )
    let arpeggio = try #require(layout.marks.first { mark in
        if case .arpeggio = mark.kind { return true }
        return false
    })

    #expect(layout.marks.filter { mark in
        if case .arpeggio = mark.kind { return true }
        return false
    }.count == 1)
    #expect(arpeggio.minimumStaffNumber == 2)
    #expect(arpeggio.maximumStaffNumber == 1)
    #expect(arpeggio.minimumStaffStep != nil)
    #expect(arpeggio.maximumStaffStep != nil)
}

@Test
func sourceBeamValuesProducePrimarySecondaryAndHookSegments() throws {
    let score = mixedSourceBeamScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    let beam = try #require(layout.beams.first)
    let firstChordID = try #require(beam.chordIDs.first)
    let lastChordID = try #require(beam.chordIDs.last)
    #expect(layout.beams.count == 1)
    #expect(beam.chordIDs.count == 4)
    #expect(beam.segments.contains {
        $0.level == 1 && $0.startChordID == firstChordID && $0.endChordID == lastChordID && $0.hookDirection == nil
    })
    #expect(beam.segments.contains {
        $0.level == 2 && $0.startChordID == beam.chordIDs[0] && $0.endChordID == beam.chordIDs[0] && $0.hookDirection == .forward
    })
    #expect(beam.segments.contains {
        $0.level == 2 && $0.startChordID == beam.chordIDs[2] && $0.endChordID == beam.chordIDs[3] && $0.hookDirection == nil
    })
}

@Test
func meterFallbackStopsAtBeatAndRestBoundaries() throws {
    let score = fallbackBeamRestScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    let beam = try #require(layout.beams.first)
    let chordsByID = Dictionary(uniqueKeysWithValues: layout.chords.map { ($0.id, $0) })
    #expect(layout.beams.count == 1)
    #expect(beam.chordIDs.compactMap { chordsByID[$0]?.tick } == [480, 720])
    #expect(layout.items.filter { $0.tick < 480 }.allSatisfy { $0.beamID == nil })
}

@Test
func unsupportedNotationUsesNeutralFallbacksWithoutChangingPerformanceFacts() throws {
    let score = unsupportedNotationScore()
    let plan = makeTestScorePerformancePlan(from: score)
    let originalEvents = plan.noteEvents
    let activeEvent = try #require(plan.noteEvents.first)
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        overlay: .init(activeEventIDs: [activeEvent.id], activeTickRange: nil)
    )

    #expect(projection.fallbacks.count == 5)
    #expect(Set(projection.fallbacks.map(\.sourceID)) == Set(score.notes.compactMap(\.sourceID)))
    #expect(projection.fallbacks.contains {
        $0.kind == .accidental && $0.reason == .microtonalAccidental && $0.placeholderPolicy == .omit
    })
    #expect(projection.fallbacks.contains {
        $0.kind == .notehead && $0.reason == .unsupportedNoteType
            && $0.placeholderPolicy == .reserveRhythmicSpace
    })
    #expect(projection.fallbacks.contains { $0.kind == .beam && $0.reason == .unsupportedBeamValue })
    #expect(projection.fallbacks.filter { $0.kind == .mark }.count == 2)

    let microtonal = try #require(layout.items.first { $0.tick == 0 })
    let neutralNotehead = try #require(layout.items.first { $0.tick == 240 })
    #expect(microtonal.displayedAccidental?.kind == .unsupported)
    #expect(microtonal.displayedAccidental?.glyphToken == nil)
    #expect(neutralNotehead.noteValue == .unsupported(sourceTypeToken: "breve"))
    #expect(neutralNotehead.noteheadGlyphToken == nil)
    #expect(neutralNotehead.xPosition.isFinite)
    #expect(layout.beams.isEmpty)
    #expect(layout.marks.allSatisfy {
        if case .articulation = $0.kind { return false }
        if case .arpeggio = $0.kind { return false }
        return true
    })
    #expect(layout.items.filter(\.isHighlighted).map(\.occurrenceID) == [activeEvent.performedNoteID.description])
    #expect(plan.noteEvents == originalEvents)

    let samples = PianoPerformanceNotationFallbackDiagnosticSample.aggregated(from: projection.fallbacks)
    let diagnosticText = samples.map(\.diagnosticEvent).map {
        "\($0.summary);\($0.reason);\($0.persistence)"
    }.joined(separator: "|")
    #expect(samples.count == 5)
    #expect(samples.allSatisfy { $0.count == 1 })
    #expect(diagnosticText.contains("kind=accidental;count=1;reason=microtonalAccidental"))
    #expect(diagnosticText.contains("SECRET-P1") == false)
    #expect(diagnosticText.contains("quarter-sharp") == false)
    #expect(diagnosticText.contains("breve") == false)
    #expect(diagnosticText.contains("feathered") == false)
    #expect(diagnosticText.contains("sideways") == false)
    #expect(samples.allSatisfy { $0.diagnosticEvent.persistence == .systemOnly })
}

@Test
func parserAndProjectionPreserveUnsupportedNoteheadAndPerformanceNotationIdentity() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <note>
          <pitch><step>C</step><octave>4</octave></pitch>
          <duration>1</duration><type>quarter</type><notehead>diamond</notehead>
          <notations>
            <ornaments><trill-mark/><mordent/></ornaments>
            <glissando type="start" number="1">gliss.</glissando>
            <breath-mark/>
          </notations>
        </note>
      </measure></part>
    </score-partwise>
    """
    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    let sourceNote = try #require(score.notes.first)
    let plan = makeTestScorePerformancePlan(from: score)
    let originalEvents = plan.noteEvents
    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let projectedNote = try #require(projection.sourceNotes.first)
    let layout = GrandStaffNotationLayoutService().makeLayout(projection: projection)
    let item = try #require(layout.items.first)

    #expect(sourceNote.noteheadToken == "diamond")
    #expect(projectedNote.noteheadToken == "diamond")
    #expect(projectedNote.performanceNotations.map(\.kind) == [
        .trillMark,
        .mordent,
        .glissando,
        .breathMark,
    ])
    #expect(projection.fallbacks.count == 5)
    #expect(projection.fallbacks.contains {
        $0.kind == .notehead && $0.sourceKindToken == "diamond"
            && $0.reason == .unsupportedNoteheadToken
            && $0.placeholderPolicy == .reserveRhythmicSpace
    })
    let markFallbacks = projection.fallbacks.filter { $0.reason == .unsupportedPerformanceNotation }
    #expect(markFallbacks.count == 4)
    #expect(Set(markFallbacks.compactMap(\.sourceNotationID)) == Set(sourceNote.performanceNotations.compactMap(\.sourceID)))
    #expect(Set(markFallbacks.compactMap(\.sourceKindToken)) == [
        "trill-mark",
        "mordent",
        "glissando",
        "breath-mark",
    ])
    #expect(item.noteheadGlyphToken == nil)
    #expect(item.xPosition.isFinite)
    #expect(plan.noteEvents == originalEvents)

    let samples = PianoPerformanceNotationFallbackDiagnosticSample.aggregated(from: projection.fallbacks)
    #expect(Set(samples.compactMap(\.sourceKindToken)) == [
        "diamond",
        "trill-mark",
        "mordent",
        "glissando",
        "breath-mark",
    ])
}

@Test
func spannersKeepNestedLevelsAndViewportContinuationSeparateByKind() throws {
    let score = notationRestAndSpannerScore()
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        ),
        viewportWidthStaffSpaces: 2,
        scrollTick: 180
    )

    #expect(layout.ties.isEmpty)
    #expect(layout.slurs.allSatisfy { $0.id.contains("slur") })
    #expect(layout.tuplets.allSatisfy { $0.id.contains("tuplet") })
    #expect(layout.tuplets.contains { $0.continuesFromPrevious || $0.continuesToNext })
}

@Test
func projectionDeduplicatesGeneratedPerformanceEventsForOneWrittenOccurrence() throws {
    let score = MusicXMLScore(notes: [notationProjectionScore().notes[0]])
    let basePlan = makeTestScorePerformancePlan(from: score)
    let sourceEvent = try #require(basePlan.noteEvents.first)
    let generatedEvents = [0, 1].map { ordinal in
        ScorePerformanceNoteEvent(
            id: ScorePerformanceNoteEventID(
                performedNoteID: sourceEvent.performedNoteID,
                generatedOrdinal: ordinal
            ),
            sourceNoteID: sourceEvent.sourceNoteID,
            performedNoteID: sourceEvent.performedNoteID,
            contributingSourceNoteIDs: sourceEvent.contributingSourceNoteIDs,
            contributingPerformedNoteIDs: sourceEvent.contributingPerformedNoteIDs,
            purpose: .ornament,
            writtenOnTick: sourceEvent.writtenOnTick,
            writtenOffTick: sourceEvent.writtenOffTick,
            performedOnTick: ordinal * 120,
            performedOffTick: ordinal * 120 + 120,
            writtenPitch: sourceEvent.writtenPitch,
            midiNote: sourceEvent.midiNote + ordinal,
            velocityResolution: sourceEvent.velocityResolution,
            staff: sourceEvent.staff,
            voice: sourceEvent.voice,
            handAssignment: sourceEvent.handAssignment,
            fingerings: sourceEvent.fingerings,
            timingProvenance: sourceEvent.timingProvenance
        )
    }
    let plan = ScorePerformancePlan(
        id: basePlan.id,
        sourceScoreIdentity: basePlan.sourceScoreIdentity,
        order: basePlan.order,
        resolution: basePlan.resolution,
        noteEvents: generatedEvents,
        tempoEvents: basePlan.tempoEvents,
        controllerEvents: basePlan.controllerEvents,
        annotations: basePlan.annotations,
        approximations: basePlan.approximations
    )

    let projection = ScoreNotationProjection(plan: plan, sourceScore: score)
    let occurrence = try #require(projection.performedOccurrences.first)
    let item = try #require(GrandStaffNotationLayoutService().makeLayout(projection: projection).items.first)

    #expect(projection.performedOccurrences.count == 1)
    #expect(occurrence.performanceEventIDs == generatedEvents.map(\.id))
    #expect(item.staffStep == -1)
}

private func notationProjectionScore() -> MusicXMLScore {
    MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 1,
                voice: 1,
                sourceOrdinal: 0
            ),
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 960,
            writtenPitch: MusicXMLWrittenPitch(step: "D", octave: 4, alter: -1, accidentalToken: "flat"),
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "half"),
            midiNote: 61,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1,
            articulations: [.staccato]
        ),
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 2,
                voice: 1,
                sourceOrdinal: 1
            ),
            partID: "P1",
            measureNumber: 1,
            tick: 960,
            durationTicks: 480,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4, alter: 1, accidentalToken: "sharp"),
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
            midiNote: 61,
            isRest: false,
            isChord: false,
            staff: 2,
            voice: 1
        ),
    ])
}

private func mixedSourceBeamScore() -> MusicXMLScore {
    let fixtures: [(tick: Int, duration: Int, type: String, beams: [MusicXMLBeam])] = [
        (0, 120, "16th", [
            .init(numberToken: "1", value: .begin, repeaterToken: nil, fanToken: nil),
            .init(numberToken: "2", value: .forwardHook, repeaterToken: nil, fanToken: nil),
        ]),
        (120, 240, "eighth", [
            .init(numberToken: "1", value: .continue, repeaterToken: nil, fanToken: nil),
        ]),
        (360, 120, "16th", [
            .init(numberToken: "1", value: .continue, repeaterToken: nil, fanToken: nil),
            .init(numberToken: "2", value: .begin, repeaterToken: nil, fanToken: nil),
        ]),
        (480, 120, "16th", [
            .init(numberToken: "1", value: .end, repeaterToken: nil, fanToken: nil),
            .init(numberToken: "2", value: .end, repeaterToken: nil, fanToken: nil),
        ]),
    ]
    return MusicXMLScore(notes: fixtures.enumerated().map { ordinal, fixture in
        notationRhythmEvent(
            ordinal: ordinal,
            tick: fixture.tick,
            duration: fixture.duration,
            type: fixture.type,
            beams: fixture.beams
        )
    })
}

private func fallbackBeamRestScore() -> MusicXMLScore {
    let notes = [
        notationRhythmEvent(ordinal: 0, tick: 0, duration: 120, type: "16th"),
        notationRhythmEvent(ordinal: 1, tick: 120, duration: 120, type: "16th", isRest: true),
        notationRhythmEvent(ordinal: 2, tick: 240, duration: 120, type: "16th"),
        notationRhythmEvent(ordinal: 3, tick: 480, duration: 240, type: "eighth"),
        notationRhythmEvent(ordinal: 4, tick: 720, duration: 240, type: "eighth"),
    ]
    return MusicXMLScore(
        notes: notes,
        timeSignatureEvents: [
            MusicXMLTimeSignatureEvent(
                tick: 0,
                beats: 4,
                beatType: 4,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )
}

private func unsupportedNotationScore() -> MusicXMLScore {
    let sourceID: (Int) -> MusicXMLSourceNoteID = { ordinal in
        MusicXMLSourceNoteID(
            partID: "SECRET-P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: 1,
            voice: 1,
            sourceOrdinal: ordinal
        )
    }
    return MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            sourceID: sourceID(0),
            partID: "SECRET-P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 240,
            writtenPitch: .init(step: "C", octave: 4, alter: 0.5, accidentalToken: "quarter-sharp"),
            writtenRhythm: .init(typeToken: "eighth"),
            midiNote: 60,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            sourceID: sourceID(1),
            partID: "SECRET-P1",
            measureNumber: 1,
            tick: 240,
            durationTicks: 240,
            writtenPitch: .init(step: "D", octave: 4),
            writtenRhythm: .init(typeToken: "breve"),
            midiNote: 62,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            sourceID: sourceID(2),
            partID: "SECRET-P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 240,
            writtenPitch: .init(step: "E", octave: 4),
            writtenRhythm: .init(typeToken: "eighth"),
            midiNote: 64,
            isRest: false,
            isChord: false,
            beams: [.init(
                numberToken: "1",
                value: .unsupported(sourceToken: "feathered"),
                repeaterToken: nil,
                fanToken: nil
            )],
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            sourceID: sourceID(3),
            partID: "SECRET-P1",
            measureNumber: 1,
            tick: 720,
            durationTicks: 240,
            writtenPitch: .init(step: "F", octave: 4),
            writtenRhythm: .init(typeToken: "eighth"),
            midiNote: 65,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1,
            articulations: [.detachedLegato],
            arpeggiate: .init(numberToken: "1", directionToken: "sideways")
        ),
    ])
}

private func notationRhythmEvent(
    ordinal: Int,
    tick: Int,
    duration: Int,
    type: String,
    beams: [MusicXMLBeam] = [],
    isRest: Bool = false
) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        sourceID: MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: tick / 1_920,
            sourceMeasureNumberToken: String(tick / 1_920 + 1),
            staff: 1,
            voice: 1,
            sourceOrdinal: ordinal
        ),
        partID: "P1",
        measureNumber: tick / 1_920 + 1,
        tick: tick,
        durationTicks: duration,
        writtenPitch: isRest ? nil : .init(step: ["C", "D", "E", "F", "G"][ordinal % 5], octave: 4),
        writtenRhythm: .init(typeToken: type),
        midiNote: isRest ? nil : 60 + ordinal,
        isRest: isRest,
        isChord: false,
        beams: beams,
        staff: 1,
        voice: 1
    )
}

private func accidentalStateScore() -> MusicXMLScore {
    let pitches: [(measure: Int, tick: Int, pitch: MusicXMLWrittenPitch, midi: Int?)] = [
        (0, 0, .init(step: "F", octave: 4, alter: 1), 66),
        (0, 120, .init(step: "F", octave: 4, accidentalToken: "natural"), 65),
        (0, 240, .init(step: "F", octave: 4), 65),
        (0, 360, .init(step: "F", octave: 4, alter: 1), 66),
        (1, 480, .init(step: "F", octave: 4), 65),
        (1, 600, .init(step: "C", octave: 5, alter: 0.5, accidentalToken: "quarter-sharp"), nil),
    ]
    let notes = pitches.enumerated().map { ordinal, fixture in
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: fixture.measure,
                sourceMeasureNumberToken: String(fixture.measure + 1),
                staff: 1,
                voice: 1,
                sourceOrdinal: ordinal
            ),
            partID: "P1",
            measureNumber: fixture.measure + 1,
            tick: fixture.tick,
            durationTicks: 120,
            writtenPitch: fixture.pitch,
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "16th"),
            midiNote: fixture.midi,
            isRest: false,
            isChord: false,
            staff: 1,
            voice: 1
        )
    }
    return MusicXMLScore(
        notes: notes,
        keySignatureEvents: [
            MusicXMLKeySignatureEvent(
                tick: 0,
                fifths: 1,
                modeToken: "major",
                scope: .init(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        transposeEvents: [
            MusicXMLTransposeEvent(
                tick: 0,
                diatonic: -1,
                chromatic: -2,
                octaveChange: 0,
                isDouble: false,
                scope: .init(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        octaveShiftEvents: [
            MusicXMLOctaveShiftEvent(
                tick: 0,
                kind: .up,
                size: 8,
                numberToken: "1",
                scope: .init(partID: "P1", staff: 1, voice: nil)
            ),
        ]
    )
}

private func notationTieScore() -> MusicXMLScore {
    MusicXMLScore(notes: [
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 0,
                sourceMeasureNumberToken: "1",
                staff: 1,
                voice: 1,
                sourceOrdinal: 0
            ),
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4),
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
            midiNote: 60,
            isRest: false,
            isChord: false,
            ties: [MusicXMLTie(
                sourceID: nil,
                sourceElement: .notation,
                typeToken: "start",
                numberToken: "1",
                placementToken: "above"
            )],
            staff: 1,
            voice: 1
        ),
        MusicXMLNoteEvent(
            sourceID: MusicXMLSourceNoteID(
                partID: "P1",
                sourceMeasureIndex: 1,
                sourceMeasureNumberToken: "2",
                staff: 1,
                voice: 1,
                sourceOrdinal: 1
            ),
            partID: "P1",
            measureNumber: 2,
            tick: 480,
            durationTicks: 480,
            writtenPitch: MusicXMLWrittenPitch(step: "C", octave: 4),
            writtenRhythm: MusicXMLWrittenRhythm(typeToken: "quarter"),
            midiNote: 60,
            isRest: false,
            isChord: false,
            ties: [MusicXMLTie(
                sourceID: nil,
                sourceElement: .notation,
                typeToken: "stop",
                numberToken: "1",
                placementToken: "above"
            )],
            staff: 1,
            voice: 1
        ),
    ])
}

private func notationRestAndSpannerScore() -> MusicXMLScore {
    let sourceID: (Int, Int, Int) -> MusicXMLSourceNoteID = { ordinal, staff, voice in
        MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: staff,
            voice: voice,
            sourceOrdinal: ordinal
        )
    }
    let rests = [
        MusicXMLNoteEvent(
            sourceID: sourceID(0, 2, 2),
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            writtenRhythm: .init(typeToken: "quarter", dotCount: 1),
            midiNote: nil,
            isRest: true,
            isPrintObjectVisible: true,
            isChord: false,
            staff: 2,
            voice: 2
        ),
        MusicXMLNoteEvent(
            sourceID: sourceID(1, 2, 2),
            partID: "P1",
            measureNumber: 1,
            tick: 480,
            durationTicks: 480,
            writtenRhythm: .init(typeToken: "quarter"),
            midiNote: nil,
            isRest: true,
            isPrintObjectVisible: false,
            isChord: false,
            staff: 2,
            voice: 2
        ),
    ]
    let pitches = ["C", "D", "E", "F"]
    let notes = pitches.enumerated().map { index, step in
        let slurs: [MusicXMLSlur] = switch index {
        case 0:
            [.init(sourceID: nil, typeToken: "start", numberToken: "2", placementToken: "above")]
        case 1:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "2", placementToken: "above")]
        case 2:
            [.init(sourceID: nil, typeToken: "start", numberToken: "2", placementToken: "below")]
        default:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "2", placementToken: "below")]
        }
        let tuplets: [MusicXMLTuplet] = switch index {
        case 0:
            [.init(sourceID: nil, typeToken: "start", numberToken: "1", bracketToken: "yes", placementToken: "above")]
        case 1:
            [.init(sourceID: nil, typeToken: "start", numberToken: "2", bracketToken: "no", placementToken: "below")]
        case 2:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "2", bracketToken: "no", placementToken: "below")]
        default:
            [.init(sourceID: nil, typeToken: "stop", numberToken: "1", bracketToken: "yes", placementToken: "above")]
        }
        return MusicXMLNoteEvent(
            sourceID: sourceID(index + 2, 1, 1),
            partID: "P1",
            measureNumber: 1,
            tick: index * 120,
            durationTicks: 120,
            writtenPitch: .init(step: step, octave: 4),
            writtenRhythm: .init(
                typeToken: "eighth",
                timeModification: .init(actualNotes: 3, normalNotes: 2)
            ),
            midiNote: 60 + index * 2,
            isRest: false,
            isChord: false,
            slurs: slurs,
            tuplets: tuplets,
            staff: 1,
            voice: 1
        )
    }
    return MusicXMLScore(notes: rests + notes)
}
