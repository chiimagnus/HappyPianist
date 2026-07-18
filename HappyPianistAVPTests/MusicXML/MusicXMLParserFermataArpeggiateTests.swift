import Foundation
@testable import HappyPianistAVP
import Testing

struct MusicXMLParserFermataArpeggiateTests {
    @Test
    func parserParsesNoteFermataAndArpeggiate() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
                <staff>1</staff>
                <voice>1</voice>
                <notations>
                  <fermata/>
                  <arpeggiate number="1" direction="up"/>
                </notations>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        let note = try #require(score.notes.first)
        #expect(note.arpeggiate == MusicXMLArpeggiate(numberToken: "1", directionToken: "up"))
        #expect(note.arpeggiate?.normalizedNumberToken == "1")
        #expect(note.arpeggiate?.direction == .up)

        #expect(score.fermataEvents.count == 1)
        let fermata = try #require(score.fermataEvents.first)
        #expect(fermata.tick == 0)
        #expect(fermata.source == .noteNotations)
        #expect(fermata.scope.partID == "P1")
        #expect(fermata.scope.staff == 1)
        #expect(fermata.scope.voice == 1)
    }

    @Test
    func parserParsesDirectionFermataWithStaffBackfill() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <direction>
                <direction-type><fermata/></direction-type>
                <staff>2</staff>
              </direction>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.fermataEvents.count == 1)
        let fermata = try #require(score.fermataEvents.first)
        #expect(fermata.source == .directionType)
        #expect(fermata.scope.staff == 2)
    }

    @Test
    func timingScheduleMergesSameNumberAcrossLogicalPianoStaves() {
        let notes = [
            makeArpeggioNote(partID: "RH", staff: 1, midi: 60, number: "7", direction: "down"),
            makeArpeggioNote(partID: "LH", staff: 2, midi: 72, number: "7", direction: "down"),
        ]
        let instrument = MusicXMLLogicalInstrument(
            id: "piano:LH+RH",
            memberPartIDs: ["LH", "RH"],
            classification: .piano,
            evidence: []
        )

        let schedule = ScoreTimingScheduleBuilder().build(
            notes: notes,
            logicalInstruments: [instrument],
            arpeggiateEnabled: true
        )

        #expect(schedule[1].performedOnTick == 0)
        #expect(schedule[0].performedOnTick == 30)
        #expect(schedule[0].provenance.contains(.arpeggio(numberToken: "7", direction: .down)))
    }

    @Test
    func timingScheduleKeepsDifferentNumbersAndUnmarkedNeighborsSeparate() {
        let notes = [
            makeArpeggioNote(partID: "P1", staff: 1, midi: 60, number: "1", direction: "up"),
            makeArpeggioNote(partID: "P1", staff: 1, midi: 67, number: "1", direction: "up"),
            makeArpeggioNote(partID: "P1", staff: 1, midi: 72, number: "2", direction: "up"),
            MusicXMLNoteEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                durationTicks: 480,
                midiNote: 64,
                isRest: false,
                isChord: true,
                tieStart: false,
                tieStop: false,
                staff: 1,
                voice: 1
            ),
        ]

        let schedule = ScoreTimingScheduleBuilder().build(notes: notes, arpeggiateEnabled: true)

        #expect(schedule[0].performedOnTick == 0)
        #expect(schedule[1].performedOnTick == 30)
        #expect(schedule[2].performedOnTick == 0)
        #expect(schedule[3].performedOnTick == 0)
    }

    private func makeArpeggioNote(
        partID: String,
        staff: Int,
        midi: Int,
        number: String,
        direction: String
    ) -> MusicXMLNoteEvent {
        MusicXMLNoteEvent(
            partID: partID,
            measureNumber: 1,
            tick: 0,
            durationTicks: 480,
            midiNote: midi,
            isRest: false,
            isChord: midi != 60,
            tieStart: false,
            tieStop: false,
            staff: staff,
            voice: 1,
            arpeggiate: MusicXMLArpeggiate(numberToken: number, directionToken: direction)
        )
    }

}

@Test
func directionOffsetMovesDirectionFermata() throws {
    let xml = """
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
    <part id="P1"><measure number="1"><attributes><divisions>2</divisions></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration></note>
      <direction><direction-type><fermata/></direction-type><offset>-1</offset></direction>
    </measure></part></score-partwise>
    """
    #expect(try MusicXMLParser().parse(data: Data(xml.utf8)).fermataEvents.first?.tick == 240)
}
