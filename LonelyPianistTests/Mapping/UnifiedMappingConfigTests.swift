import Foundation
import Testing
@testable import LonelyPianist

@MainActor
@Test
func keyStrokeCodableAndDisplayOrderStable() throws {
    let stroke = KeyStroke(keyCode: 40, modifiers: [.shift, .command, .option, .control])
    let data = try JSONEncoder().encode(stroke)
    let decoded = try JSONDecoder().decode(KeyStroke.self, from: data)

    #expect(decoded == stroke)
    #expect(decoded.displayLabel == "\u{2318}\u{2325}\u{2303}\u{21E7}K")
}

@MainActor
@Test
func keyStrokeDisplayFallsBackToNumericKeyCode() {
    let stroke = KeyStroke(keyCode: 999)
    #expect(stroke.displayLabel == "999")
}

@MainActor
@Test
func mappingEngineAppliesVelocityShiftDerivation() {
    let engine = DefaultMappingEngine()
    let payload = MappingConfigPayload(
        velocityEnabled: true,
        defaultVelocityThreshold: 100,
        singleKeyRules: [
            SingleKeyMappingRule(note: 60, output: KeyStroke(keyCode: 40), velocityThreshold: 100)
        ],
        chordRules: []
    )

    let low = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 90), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(low.count == 1)
    #expect(low.first?.keyStroke == KeyStroke(keyCode: 40))

    _ = engine.process(
        event: MIDIEvent(type: .noteOff(note: 60, velocity: 0), channel: 1, timestamp: .now),
        payload: payload
    )

    let high = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 120), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(high.count == 1)
    #expect(high.first?.keyStroke == KeyStroke(keyCode: 40, modifiers: [.shift]))
}

@MainActor
@Test
func mappingEngineUsesNormalOutputWhenVelocityDisabled() {
    let engine = DefaultMappingEngine()
    let payload = MappingConfigPayload(
        velocityEnabled: false,
        defaultVelocityThreshold: 20,
        singleKeyRules: [
            SingleKeyMappingRule(note: 60, output: KeyStroke(keyCode: 40), velocityThreshold: 1)
        ],
        chordRules: []
    )

    let resolved = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 127), channel: 1, timestamp: .now),
        payload: payload
    )

    #expect(resolved.count == 1)
    #expect(resolved.first?.keyStroke == KeyStroke(keyCode: 40))
}

@MainActor
@Test
func mappingEngineChordUsesStrictEquality() {
    let engine = DefaultMappingEngine()
    let payload = MappingConfigPayload(
        velocityEnabled: false,
        defaultVelocityThreshold: 100,
        singleKeyRules: [],
        chordRules: [
            ChordMappingRule(notes: [60, 64, 67], output: KeyStroke(keyCode: 8, modifiers: [.command]))
        ]
    )

    let first = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(first.isEmpty)

    let second = engine.process(
        event: MIDIEvent(type: .noteOn(note: 64, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(second.isEmpty)

    let matched = engine.process(
        event: MIDIEvent(type: .noteOn(note: 67, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(matched.count == 1)

    let extra = engine.process(
        event: MIDIEvent(type: .noteOn(note: 69, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(extra.isEmpty)
}

@MainActor
@Test
func mappingConfigPayloadCodableRoundTrip() throws {
    let payload = MappingConfigPayload(
        velocityEnabled: true,
        defaultVelocityThreshold: 77,
        singleKeyRules: [
            SingleKeyMappingRule(note: 60, output: KeyStroke(keyCode: 0), velocityThreshold: 77)
        ],
        chordRules: [
            ChordMappingRule(notes: [60, 64, 67], output: KeyStroke(keyCode: 8, modifiers: [.command]))
        ]
    )

    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(MappingConfigPayload.self, from: data)
    #expect(decoded == payload)
}
