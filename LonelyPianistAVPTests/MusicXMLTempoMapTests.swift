import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func tempoMapFixedBPMTickToSeconds() {
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120),
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
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120),
            MusicXMLTempoEvent(tick: 480, quarterBPM: 60),
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
            MusicXMLTempoEvent(tick: 480, quarterBPM: 60),
        ]
    )

    #expect(abs(map.timeSeconds(atTick: 480) - 1.0) < 0.000_1)
}
