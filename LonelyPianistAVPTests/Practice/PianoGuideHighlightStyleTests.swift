@testable import LonelyPianistAVP
import Testing

@Test
func styleResolvesRightHandWhiteKeyTriggered() {
    let style = PianoGuideHighlightStyle.resolve(hand: .right, phase: .triggered, keyKind: .white)
    #expect(style.tintToken == .rightHandWhiteKey)
    #expect(style.opacity == 0.90)
}

@Test
func styleResolvesRightHandWhiteKeyActive() {
    let style = PianoGuideHighlightStyle.resolve(hand: .right, phase: .active, keyKind: .white)
    #expect(style.tintToken == .rightHandWhiteKey)
    #expect(style.opacity == 0.48)
}

@Test
func styleResolvesLeftHandWhiteKeyActive() {
    let style = PianoGuideHighlightStyle.resolve(hand: .left, phase: .active, keyKind: .white)
    #expect(style.tintToken == .leftHandKey)
    #expect(style.opacity == 0.55)
}

@Test
func styleResolvesRightHandBlackKeyActiveMatchesTriggered() {
    let active = PianoGuideHighlightStyle.resolve(hand: .right, phase: .active, keyKind: .black)
    let triggered = PianoGuideHighlightStyle.resolve(hand: .right, phase: .triggered, keyKind: .black)
    #expect(active.tintToken == .rightHandBlackKey)
    #expect(triggered.tintToken == .rightHandBlackKey)
    #expect(active.opacity == 0.95)
    #expect(triggered.opacity == 0.95)
}

@Test
func styleResolvesLeftHandBlackKeyActive() {
    let style = PianoGuideHighlightStyle.resolve(hand: .left, phase: .active, keyKind: .black)
    #expect(style.tintToken == .leftHandKey)
    #expect(style.opacity == 0.92)
}
