import Foundation
@testable import MusicXML
@testable import HappyPianistAVP
import Testing

struct MusicXMLParserPerformanceTimingTests {
    @Test
    func parserParsesNoteAttackAndReleaseIntoTicks() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>2</divisions></attributes>
              <note attack="1" release="1">
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>2</duration><type>quarter</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let score = try MusicXMLParser().parse(data: Data(xml.utf8))
        #expect(score.notes.count == 1)
        #expect(score.notes.first?.attackTicks == MusicXMLTempoMap.ticksPerQuarter / 2)
        #expect(score.notes.first?.releaseTicks == MusicXMLTempoMap.ticksPerQuarter / 2)
    }
}

@Test
func directionOffsetResolverNormalizesDivisionsAndAllowsCrossMeasureOffsets() {
    let resolver = MusicXMLDirectionOffsetResolver(ticksPerQuarter: 480)

    #expect(resolver.offsetTicks(rawDivisions: 1.5, divisions: 2) == 360)
    #expect(resolver.offsetTicks(rawDivisions: -2, divisions: 2) == -480)
    #expect(resolver.offsetTicks(rawDivisions: .nan, divisions: 2) == nil)
    #expect(resolver.absoluteTick(directionStartTick: 960, offsetTicks: -480) == 480)
    #expect(resolver.absoluteTick(directionStartTick: 240, offsetTicks: -480) == 0)
}

@Test
func directionOffsetCanMovePlaybackFactIntoPreviousMeasure() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1">
        <measure number="1">
          <attributes><divisions>1</divisions></attributes>
          <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
        </measure>
        <measure number="2">
          <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration><type>quarter</type></note>
          <direction>
            <direction-type><words>dolce</words></direction-type>
            <offset sound="yes">-2</offset>
          </direction>
        </measure>
      </part>
    </score-partwise>
    """

    let event = try #require(MusicXMLParser().parse(data: Data(xml.utf8)).wordsEvents.first)
    #expect(event.tick == 0)
}
