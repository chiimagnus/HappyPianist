import Foundation
@testable import Practice
import Testing

@Test
func keyboardLayoutSortsKeysAndRejectsAmbiguousOrInvalidCoordinates() {
    let layout = PianoFingeringKeyboardLayout(keys: [
        .init(midiNote: 64, kind: .white, localX: 0.04),
        .init(midiNote: 60, kind: .white, localX: 0),
        .init(midiNote: 61, kind: .black, localX: 0.01),
    ])

    #expect(layout.keys.map(\.midiNote) == [60, 61, 64])
    #expect(layout.key(forMIDINote: 61)?.kind == .black)
    #expect(layout.key(forMIDINote: 62) == nil)

    let invalid = PianoFingeringKeyboardLayout(keys: [
        .init(midiNote: 60, kind: .white, localX: 0),
        .init(midiNote: 60, kind: .white, localX: 0.02),
        .init(midiNote: 61, kind: .black, localX: .nan),
    ])
    #expect(invalid.key(forMIDINote: 60) == nil)
    #expect(invalid.key(forMIDINote: 61) == nil)
}
