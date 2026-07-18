@testable import HappyPianistAVP
import Testing

private let hostTimeTestScope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)

@Test
func midi2Value16To7BitKeepsZeroAndNeverMapsNonZeroToZero() {
    #expect(MIDI2ValueMapping.value16To7Bit(0) == 0)
    #expect(MIDI2ValueMapping.value16To7Bit(1) >= 1)
    #expect(MIDI2ValueMapping.value16To7Bit(UInt16.max) == 127)

    for value in [UInt16(1), 2, 100, 1000, UInt16.max] {
        let mapped = MIDI2ValueMapping.value16To7Bit(value)
        #expect((1 ... 127).contains(mapped))
    }
}

@Test
func midi2Value32To7BitKeepsZeroAndNeverMapsNonZeroToZero() {
    #expect(MIDI2ValueMapping.value32To7Bit(0) == 0)
    #expect(MIDI2ValueMapping.value32To7Bit(1) >= 1)
    #expect(MIDI2ValueMapping.value32To7Bit(UInt32.max) == 127)

    for value in [UInt32(1), 2, 100, 1000, UInt32.max] {
        let mapped = MIDI2ValueMapping.value32To7Bit(value)
        #expect((1 ... 127).contains(mapped))
    }
}

@Test
func midi2PitchBendMapsTo14BitRange() {
    #expect(MIDI2ValueMapping.pitchBend32To14Bit(0) == 0)
    #expect(MIDI2ValueMapping.pitchBend32To14Bit(UInt32.max) == 16383)
}

@Test
func midiHostTimeConverterConsumesTempoPauseAndSeekAdjustedTransportTime() {
    let tempoMap = MusicXMLTempoMap(tempoEvents: [
        MusicXMLTempoEvent(tick: 0, quarterBPM: 120, scope: hostTimeTestScope),
        MusicXMLTempoEvent(tick: 480, quarterBPM: 60, scope: hostTimeTestScope),
    ])
    let timeline = AutoplayPerformanceTimeline(events: [
        .init(id: 0, tick: 0, kind: .noteOn(midi: 60, velocity: 90)),
        .init(id: 1, tick: 480, kind: .pauseSeconds(1)),
        .init(id: 2, tick: 480, kind: .noteOn(midi: 62, velocity: 90)),
        .init(id: 3, tick: 960, kind: .noteOff(midi: 62)),
    ])
    let schedule = PracticeSequencerSequenceBuilder().buildPerformanceEventSchedule(
        timeline: timeline,
        tempoMap: tempoMap,
        startTick: 0
    )
    let converter = MIDIHostTimeConverter(
        currentHostTime: { 10_000 },
        hostTicksPerSecond: 1_000
    )
    let origin = converter.origin(atTransportSeconds: schedule[1].timeSeconds)

    #expect(schedule.map(\.timeSeconds) == [0, 1.5, 2.5])
    #expect(converter.hostTime(atTransportSeconds: schedule[1].timeSeconds, relativeTo: origin) == 10_000)
    #expect(converter.hostTime(atTransportSeconds: schedule[2].timeSeconds, relativeTo: origin) == 11_000)
}

@Test
func midiHostTimeConverterSaturatesLargeTransportValuesWithoutOverflow() {
    let converter = MIDIHostTimeConverter(
        currentHostTime: { UInt64.max - 10 },
        hostTicksPerSecond: 1_000_000_000
    )
    let origin = converter.origin(atTransportSeconds: 0)

    #expect(converter.hostTime(atTransportSeconds: .greatestFiniteMagnitude, relativeTo: origin) == .max)
}
