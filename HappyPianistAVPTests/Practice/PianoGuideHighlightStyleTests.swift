@testable import HappyPianistAVP
import Testing

@Test
func styleResolvesUpperStaffWhiteKeyTriggered() {
    let style = PianoGuideHighlightStyle.resolve(staffNumber: 1, phase: .triggered, keyKind: .white)
    #expect(style.tintToken == .upperStaffWhiteKey)
    #expect(style.opacity == 0.75)
}

@Test
func styleResolvesUpperStaffWhiteKeyActive() {
    let style = PianoGuideHighlightStyle.resolve(staffNumber: 1, phase: .active, keyKind: .white)
    #expect(style.tintToken == .upperStaffWhiteKey)
    #expect(style.opacity == 0.48)
}

@Test
func styleResolvesLowerStaffWhiteKeyActive() {
    let style = PianoGuideHighlightStyle.resolve(staffNumber: 2, phase: .active, keyKind: .white)
    #expect(style.tintToken == .lowerStaffKey)
    #expect(style.opacity == 0.55)
}

@Test
func styleResolvesUpperStaffBlackKeyActiveMatchesTriggered() {
    let active = PianoGuideHighlightStyle.resolve(staffNumber: 1, phase: .active, keyKind: .black)
    let triggered = PianoGuideHighlightStyle.resolve(staffNumber: 1, phase: .triggered, keyKind: .black)
    #expect(active.tintToken == .upperStaffBlackKey)
    #expect(triggered.tintToken == .upperStaffBlackKey)
    #expect(active.opacity == 0.95)
    #expect(triggered.opacity == 0.95)
}

@Test
func styleResolvesLowerStaffBlackKeyActive() {
    let style = PianoGuideHighlightStyle.resolve(staffNumber: 2, phase: .active, keyKind: .black)
    #expect(style.tintToken == .lowerStaffKey)
    #expect(style.opacity == 0.92)
}

@Test
func styleKeepsMissingAndAdditionalStavesNeutral() {
    #expect(PianoGuideHighlightStyle.resolve(
        staffNumber: nil,
        phase: .triggered,
        keyKind: .white
    ).tintToken == .unassignedStaffKey)
    #expect(PianoGuideHighlightStyle.resolve(
        staffNumber: 3,
        phase: .triggered,
        keyKind: .white
    ).tintToken == .unassignedStaffKey)
}
