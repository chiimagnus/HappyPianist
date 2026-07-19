import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func pedalTimelinePreservesExactControllerValues() {
    let timeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                kind: .start,
                value: .on,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 480,
                kind: .stop,
                value: .off,
                timeOnlyPasses: nil
            ),
        ]
    )

    let changes = timeline.controllerChanges()
    #expect(changes.map(\.tick) == [0, 480])
    #expect(changes.map(\.controllerNumber) == [64, 64])
    #expect(changes.map(\.value) == [127, 0])
}

@Test
func pedalTimelineIgnoresValuelessContinueAndPreservesSameTickValues() {
    let timeline = MusicXMLPedalTimeline(
        events: [
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 0,
                kind: .continue,
                value: nil,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 120,
                kind: .change,
                value: .off,
                timeOnlyPasses: nil
            ),
            MusicXMLPedalEvent(
                partID: "P1",
                measureNumber: 1,
                tick: 120,
                kind: .change,
                value: .on,
                timeOnlyPasses: nil
            ),
        ]
    )

    let changes = timeline.controllerChanges()
    #expect(changes.map(\.tick) == [120, 120])
    #expect(changes.map(\.value) == [0, 127])
}

@Test
func pedalTimelinePreservesContinuousDamperSostenutoAndSoftValues() throws {
    let damper = try #require(MusicXMLControllerValue(musicXMLString: "42.5"))
    let soft = try #require(MusicXMLControllerValue(musicXMLString: "25"))
    let timeline = MusicXMLPedalTimeline(events: [
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 0,
            kind: .change,
            value: damper,
            timeOnlyPasses: nil
        ),
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 120,
            kind: .start,
            controller: .sostenuto,
            value: .on,
            timeOnlyPasses: nil
        ),
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 240,
            kind: .change,
            controller: .soft,
            value: soft,
            timeOnlyPasses: nil
        ),
    ])

    #expect(damper.percentage == Decimal(string: "42.5"))
    #expect(damper.midiValue == 54)
    #expect(timeline.controllerChanges().map(\.controllerNumber) == [64, 66, 67])
    #expect(timeline.controllerChanges().map(\.value) == [54, 127, 32])
    #expect(MusicXMLControllerValue(musicXMLString: "-0.1") == nil)
    #expect(MusicXMLControllerValue(musicXMLString: "100.1") == nil)
}

@Test
func pedalTimelinePreservesSameTickControllerSourceOrder() {
    let timeline = MusicXMLPedalTimeline(events: [
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 120,
            kind: .start,
            value: .on,
            timeOnlyPasses: nil
        ),
        MusicXMLPedalEvent(
            partID: "P1",
            measureNumber: 1,
            tick: 120,
            kind: .stop,
            value: .off,
            timeOnlyPasses: nil
        ),
    ])

    #expect(timeline.controllerChanges().map(\.value) == [127, 0])
}

@Test
func parserReadsContinuousSoundPedalFacts() throws {
    let xml = """
    <score-partwise version="4.0">
      <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
      <part id="P1"><measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <direction><sound damper-pedal="42.5" sostenuto-pedal="yes" soft-pedal="25"/></direction>
        <note><rest/><duration>1</duration></note>
      </measure></part>
    </score-partwise>
    """

    let score = try MusicXMLParser().parse(data: Data(xml.utf8))
    #expect(score.pedalEvents.map(\.controller) == [.damper, .sostenuto, .soft])
    #expect(score.pedalEvents.compactMap(\.value?.midiValue) == [54, 127, 32])
    #expect(score.pedalEvents.map(\.sourceID).allSatisfy { $0 != nil })
}
