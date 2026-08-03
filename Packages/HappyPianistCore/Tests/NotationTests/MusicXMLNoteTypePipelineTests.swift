import Foundation
@testable import MusicXML
@testable import Notation
@testable import Practice
import Testing

@Test
func everyStandardMusicXMLNoteTypeFlowsFromParserToNotationLayout() throws {
    let score = try MusicXMLParser().parse(data: Data(standardRhythmMusicXML.utf8))
    let expectedTypes = MusicXMLNoteType.allCases

    #expect(expectedTypes.map(\.rawValue) == [
        "1024th", "512th", "256th", "128th", "64th", "32nd", "16th",
        "eighth", "quarter", "half", "whole", "breve", "long", "maxima",
    ])
    #expect(score.notes.filter { $0.isRest == false }.compactMap { $0.writtenRhythm?.noteType } == expectedTypes)
    #expect(score.notes.filter(\.isRest).compactMap { $0.writtenRhythm?.noteType } == expectedTypes)
    #expect(score.notes.first?.durationTicks == 15)

    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        viewportWidthStaffSpaces: 10_000
    )

    #expect(projection.fallbacks.isEmpty)
    #expect(layout.items.map(\.noteType) == expectedTypes)
    #expect(layout.rests.map(\.noteType) == expectedTypes)
    #expect(layout.items.compactMap(\.noteheadGlyphToken) == [
        .noteheadBlack, .noteheadBlack, .noteheadBlack, .noteheadBlack, .noteheadBlack,
        .noteheadBlack, .noteheadBlack, .noteheadBlack, .noteheadBlack, .noteheadHalf,
        .noteheadWhole, .noteheadDoubleWhole, .mensuralWhiteLonga, .mensuralWhiteMaxima,
    ])
    #expect(layout.rests.compactMap(\.glyphToken) == [
        .restOneThousandTwentyFourth, .restFiveHundredTwelfth, .restTwoHundredFiftySixth,
        .restOneHundredTwentyEighth, .restSixtyFourth, .restThirtySecond, .restSixteenth,
        .restEighth, .restQuarter, .restHalf, .restWhole, .restDoubleWhole, .restLonga, .restMaxima,
    ])
    #expect(layout.chords.filter { [.maxima, .long, .breve, .whole].contains($0.noteType) }.allSatisfy { $0.stem.isVisible == false })
    #expect(layout.chords.filter { [.half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth, .oneHundredTwentyEighth, .twoHundredFiftySixth, .fiveHundredTwelfth, .oneThousandTwentyFourth].contains($0.noteType) }.allSatisfy { $0.stem.isVisible })
}

@Test
func oneThousandTwentyFourthNotesUseAllEightFallbackBeamLevels() {
    let score = MusicXMLScore(notes: [
        makeOneThousandTwentyFourthNote(ordinal: 0, tick: 0),
        makeOneThousandTwentyFourthNote(ordinal: 1, tick: 15),
    ])
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: ScoreNotationProjection(
            plan: makeTestScorePerformancePlan(from: score),
            sourceScore: score
        )
    )

    #expect(Set(layout.beams.flatMap(\.segments).map(\.level)) == Set(1 ... 8))
}

@Test
func parserRejectsMissingAndUnsupportedWrittenRhythms() {
    for (replacement, expected) in [
        ("", MusicXMLWrittenRhythmFailure.missingType),
        ("<type>Quarter</type>", .unsupportedType),
        ("<type>quarter</type>", .missingDuration),
    ] {
        let xml = """
        <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
        <part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes>
        <note><pitch><step>C</step><octave>4</octave></pitch>\(replacement == "<type>quarter</type>" ? "" : "<duration>1</duration>")\(replacement)</note>
        </measure></part></score-partwise>
        """

        #expect(throws: MusicXMLParserError.invalidWrittenRhythm(expected)) {
            try MusicXMLParser().parse(data: Data(xml.utf8))
        }
    }
}

private let standardRhythmMusicXML = """
<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1"><attributes><divisions>256</divisions></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><type>1024th</type></note><note><rest/><duration>1</duration><type>1024th</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>2</duration><type>512th</type></note><note><rest/><duration>2</duration><type>512th</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration><type>256th</type></note><note><rest/><duration>4</duration><type>256th</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>8</duration><type>128th</type></note><note><rest/><duration>8</duration><type>128th</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>16</duration><type>64th</type></note><note><rest/><duration>16</duration><type>64th</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>32</duration><type>32nd</type></note><note><rest/><duration>32</duration><type>32nd</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>64</duration><type>16th</type></note><note><rest/><duration>64</duration><type>16th</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>128</duration><type>eighth</type></note><note><rest/><duration>128</duration><type>eighth</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>256</duration><type>quarter</type></note><note><rest/><duration>256</duration><type>quarter</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>512</duration><type>half</type></note><note><rest/><duration>512</duration><type>half</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>1024</duration><type>whole</type></note><note><rest/><duration>1024</duration><type>whole</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>2048</duration><type>breve</type></note><note><rest/><duration>2048</duration><type>breve</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>4096</duration><type>long</type></note><note><rest/><duration>4096</duration><type>long</type></note>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>8192</duration><type>maxima</type></note><note><rest/><duration>8192</duration><type>maxima</type></note>
</measure></part></score-partwise>
"""

private func makeOneThousandTwentyFourthNote(ordinal: Int, tick: Int) -> MusicXMLNoteEvent {
    MusicXMLNoteEvent(
        sourceID: MusicXMLSourceNoteID(
            partID: "P1",
            sourceMeasureIndex: 0,
            sourceMeasureNumberToken: "1",
            staff: 1,
            voice: 1,
            sourceOrdinal: ordinal
        ),
        partID: "P1",
        measureNumber: 1,
        tick: tick,
        durationTicks: 15,
        writtenPitch: .init(step: ordinal == 0 ? "C" : "D", octave: 4),
        writtenRhythm: .init(noteType: .oneThousandTwentyFourth),
        midiNote: 60 + ordinal,
        isRest: false,
        isChord: false,
        staff: 1,
        voice: 1
    )
}
