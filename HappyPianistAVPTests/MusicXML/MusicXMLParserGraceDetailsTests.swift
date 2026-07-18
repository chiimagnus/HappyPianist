import Foundation
@testable import HappyPianistAVP
import Testing

struct MusicXMLParserGraceDetailsTests {
    @Test
    func parserParsesGraceSlashAndStealTimeAttributes() throws {
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
                <grace slash="yes" steal-time-following="25"/>
                <pitch><step>C</step><octave>4</octave></pitch>
                <type>eighth</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        let note = try #require(score.notes.first)
        #expect(note.isGrace == true)
        #expect(note.graceSlash == true)
        #expect(note.graceStealTimePrevious == nil)
        #expect(note.graceStealTimeFollowing == 0.25)
    }

    @Test
    func parserConvertsGraceMakeTimeFromDivisionsToTicks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>4</divisions></attributes>
              <note>
                <grace make-time="1.5"/>
                <pitch><step>D</step><octave>4</octave></pitch>
                <type>16th</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let note = try #require(MusicXMLParser().parse(data: Data(xml.utf8)).notes.first)
        #expect(note.graceMakeTimeTicks == 180)
    }

    @Test
    func scheduleStealsPreviousAndFollowingFromTheirOwnAnchors() {
        let notes = [
            makeNote(tick: 0, duration: 480, midi: 60),
            makeNote(
                tick: 480,
                duration: 0,
                midi: 62,
                isGrace: true,
                stealPrevious: 0.25,
                stealFollowing: 0.125
            ),
            makeNote(tick: 480, duration: 480, midi: 64),
        ]

        let schedule = ScoreTimingScheduleBuilder().build(notes: notes)

        #expect(schedule[0].performedOffTick == 360)
        #expect(schedule[1].performedOnTick == 360)
        #expect(schedule[1].performedOffTick == 540)
        #expect(schedule[2].performedOnTick == 540)
        #expect(schedule[2].performedOffTick == 960)
        #expect(schedule[1].releasePolicy == .graceStealPreviousAndFollowing)
    }

    @Test
    func scheduleMakeTimeShiftsFollowingMeasuresWithoutStealing() {
        let notes = [
            makeNote(tick: 0, duration: 480, midi: 60, measure: 1),
            makeNote(tick: 480, duration: 0, midi: 62, measure: 2, isGrace: true, makeTime: 120),
            makeNote(tick: 480, duration: 480, midi: 64, measure: 2),
            makeNote(tick: 960, duration: 480, midi: 65, measure: 3),
        ]

        let schedule = ScoreTimingScheduleBuilder().build(notes: notes)

        #expect(schedule[0].performedOnTick == 0)
        #expect(schedule[0].performedOffTick == 480)
        #expect(schedule[1].performedOnTick == 480)
        #expect(schedule[1].performedOffTick == 600)
        #expect(schedule[2].performedOnTick == 600)
        #expect(schedule[2].performedOffTick == 1080)
        #expect(schedule[3].performedOnTick == 1080)
        #expect(schedule[3].performedOffTick == 1560)
    }

    @Test
    func scheduleKeepsInvalidPreviousStealAsUnresolvedEvidence() {
        let notes = [
            makeNote(tick: 0, duration: 0, midi: 62, isGrace: true, stealPrevious: 0.25),
            makeNote(tick: 0, duration: 480, midi: 64),
        ]

        let schedule = ScoreTimingScheduleBuilder().build(notes: notes)

        #expect(schedule[0].performedOnTick == 0)
        #expect(schedule[0].performedOffTick == 0)
        #expect(schedule[0].provenance.contains(.approximation(reason: "grace-steal-previous-missing-anchor")))
        #expect(schedule[1].performedOnTick == 0)
    }

    private func makeNote(
        tick: Int,
        duration: Int,
        midi: Int,
        measure: Int = 1,
        isGrace: Bool = false,
        stealPrevious: Double? = nil,
        stealFollowing: Double? = nil,
        makeTime: Int? = nil
    ) -> MusicXMLNoteEvent {
        MusicXMLNoteEvent(
            partID: "P1",
            measureNumber: measure,
            tick: tick,
            durationTicks: duration,
            midiNote: midi,
            isRest: false,
            isChord: false,
            isGrace: isGrace,
            graceStealTimePrevious: stealPrevious,
            graceStealTimeFollowing: stealFollowing,
            graceMakeTimeTicks: makeTime,
            tieStart: false,
            tieStop: false,
            staff: 1,
            voice: 1
        )
    }

}
