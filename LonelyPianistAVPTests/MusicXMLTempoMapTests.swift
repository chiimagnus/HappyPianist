import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func tempoMapFixedBPMTickToSeconds() {
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: 0,
                quarterBPM: 120,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )

    #expect(abs(map.timeSeconds(atTick: 0) - 0) < 0.000_1)
    #expect(abs(map.timeSeconds(atTick: 480) - 0.5) < 0.000_1)
    #expect(abs(map.timeSeconds(atTick: 960) - 1.0) < 0.000_1)
    #expect(abs(map.durationSeconds(fromTick: 480, toTick: 960) - 0.5) < 0.000_1)
}

@Test
func tempoMapIntegratesAcrossTempoChange() {
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: 0,
                quarterBPM: 120,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
            MusicXMLTempoEvent(
                tick: 480,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )

    #expect(abs(map.durationSeconds(fromTick: 0, toTick: 480) - 0.5) < 0.000_1)
    #expect(abs(map.durationSeconds(fromTick: 480, toTick: 960) - 1.0) < 0.000_1)
    #expect(abs(map.timeSeconds(atTick: 960) - 1.5) < 0.000_1)
}

@Test
func tempoMapInsertsTickZeroWhenFirstEventIsLater() {
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: 480,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )

    #expect(abs(map.timeSeconds(atTick: 480) - 1.0) < 0.000_1)
}

@Test
func tempoMapIntegratesAcrossLinearRitardandoRamp() {
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: 0,
                quarterBPM: 120,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
            MusicXMLTempoEvent(
                tick: 480,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        tempoRamps: [
            MusicXMLTempoMap.TempoRamp(startTick: 0, endTick: 480, startQuarterBPM: 120, endQuarterBPM: 60),
        ]
    )

    #expect(abs(map.durationSeconds(fromTick: 0, toTick: 480) - log(2)) < 0.000_1)
}
