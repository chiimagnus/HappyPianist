import Foundation
@testable import LonelyPianistAVP
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
              <slur type="start" number="1"/>
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
    #expect(score.slurEvents.isEmpty == false)
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
        expressivity: expressivity,
        fermataTimeline: fermataTimeline
    )
    let c4Span = spans.first(where: { $0.midiNote == 60 })
    let e4Span = spans.first(where: { $0.midiNote == 64 })
    #expect(c4Span?.onTick == 0)
    #expect(e4Span?.onTick == 30)
    #expect(c4Span?.offTick == 720)
}
