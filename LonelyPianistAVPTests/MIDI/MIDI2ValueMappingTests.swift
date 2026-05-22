@testable import LonelyPianistAVP
import Testing

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
