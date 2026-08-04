import Foundation
@testable import MusicXML
@testable import HappyPianistAVP
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
    #expect(abs(map.timeSeconds(atTick: MusicXMLTempoMap.ticksPerQuarter) - 0.5) < 0.000_1)
    #expect(abs(map.timeSeconds(atTick: MusicXMLTempoMap.ticksPerQuarter * 2) - 1.0) < 0.000_1)
    #expect(abs(map.durationSeconds(fromTick: MusicXMLTempoMap.ticksPerQuarter, toTick: MusicXMLTempoMap.ticksPerQuarter * 2) - 0.5) < 0.000_1)
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
                tick: MusicXMLTempoMap.ticksPerQuarter,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )

    #expect(abs(map.durationSeconds(fromTick: 0, toTick: MusicXMLTempoMap.ticksPerQuarter) - 0.5) < 0.000_1)
    #expect(abs(map.durationSeconds(fromTick: MusicXMLTempoMap.ticksPerQuarter, toTick: MusicXMLTempoMap.ticksPerQuarter * 2) - 1.0) < 0.000_1)
    #expect(abs(map.timeSeconds(atTick: MusicXMLTempoMap.ticksPerQuarter * 2) - 1.5) < 0.000_1)
}

@Test
func tempoMapInsertsTickZeroWhenFirstEventIsLater() {
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(
                tick: MusicXMLTempoMap.ticksPerQuarter,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ]
    )

    #expect(abs(map.timeSeconds(atTick: MusicXMLTempoMap.ticksPerQuarter) - 1.0) < 0.000_1)
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
                tick: MusicXMLTempoMap.ticksPerQuarter,
                quarterBPM: 60,
                scope: MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
            ),
        ],
        tempoRamps: [
            MusicXMLTempoMap.TempoRamp(startTick: 0, endTick: MusicXMLTempoMap.ticksPerQuarter, startQuarterBPM: 120, endQuarterBPM: 60),
        ]
    )

    #expect(abs(map.durationSeconds(fromTick: 0, toTick: MusicXMLTempoMap.ticksPerQuarter) - log(2)) < 0.000_1)
}

@Test
func tempoMapReportsTickDomainBPMInsideRamp() {
    let scope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    let map = MusicXMLTempoMap(
        tempoEvents: [
            MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: scope),
            MusicXMLTempoEvent(tick: MusicXMLTempoMap.ticksPerQuarter, quarterBPM: 60, scope: scope),
        ],
        tempoRamps: [
            MusicXMLTempoMap.TempoRamp(
                startTick: 0,
                endTick: MusicXMLTempoMap.ticksPerQuarter,
                startQuarterBPM: 120,
                endQuarterBPM: 60,
                scope: scope
            ),
        ]
    )

    #expect(map.quarterBPM(atTick: 0) == 120)
    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter / 4) == 105)
    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter / 2) == 90)
    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter * 3 / 4) == 75)
    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter) == 60)
}

@Test
func tempoMapDerivedFromPerformancePlanKeepsRampEndpointTempo() {
    let map = MusicXMLTempoMap(performanceEvents: [
        ScorePerformanceTempoEvent(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: 0,
            quarterBPM: 120,
            endTick: nil,
            endQuarterBPM: nil
        ),
        ScorePerformanceTempoEvent(
            sourceDirectionID: nil,
            performedOccurrenceIndex: 0,
            tick: MusicXMLTempoMap.ticksPerQuarter,
            quarterBPM: 120,
            endTick: MusicXMLTempoMap.ticksPerQuarter * 2,
            endQuarterBPM: 60
        ),
    ])

    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter * 3 / 2) == 90)
    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter * 2) == 60)
    #expect(map.quarterBPM(atTick: MusicXMLTempoMap.ticksPerQuarter * 3) == 60)
    #expect(abs(map.durationSeconds(fromTick: MusicXMLTempoMap.ticksPerQuarter * 2, toTick: MusicXMLTempoMap.ticksPerQuarter * 3) - 1) < 0.000_1)
}
