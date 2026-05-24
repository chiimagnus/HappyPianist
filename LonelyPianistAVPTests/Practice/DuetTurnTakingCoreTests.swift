import ImprovProtocol
@testable import LonelyPianistAVP
import Testing

@Test
func duetTurnTakingCoreShortPhraseSchedulesAfterReleaseAll() {
    var core = DuetTurnTakingCore()
    #expect(core.handle(.noteOn(note: 60, velocity: 90, timestampSeconds: 10.0)) == .none)

    let decision = core.handle(.noteOff(note: 60, timestampSeconds: 10.1))
    guard case let .scheduleSend(deadlineTimestampSeconds: deadline) = decision else {
        #expect(Bool(false))
        return
    }
    #expect(abs(deadline - 10.7) < 1e-9)
    #expect(core.hasPendingSend)
}

@Test
func duetTurnTakingCoreLongPhraseSendsImmediately() {
    var core = DuetTurnTakingCore()
    _ = core.handle(.noteOn(note: 60, velocity: 90, timestampSeconds: 1.0))

    let decision = core.handle(.noteOff(note: 60, timestampSeconds: 4.1))
    #expect(decision == .sendNow)
    #expect(core.hasPendingSend == false)
}

@Test
func duetTurnTakingCoreNoteOnCancelsPendingSend() {
    var core = DuetTurnTakingCore()
    _ = core.handle(.noteOn(note: 60, velocity: 90, timestampSeconds: 1.0))
    let scheduleDecision = core.handle(.noteOff(note: 60, timestampSeconds: 1.2))
    guard case let .scheduleSend(deadlineTimestampSeconds: deadline) = scheduleDecision else {
        #expect(Bool(false))
        return
    }
    #expect(abs(deadline - 1.8) < 1e-9)
    #expect(core.handle(.noteOn(note: 64, velocity: 90, timestampSeconds: 1.3)) == .cancelPendingSend)
    #expect(core.hasPendingSend == false)
}

@Test
func duetTurnTakingCoreHeldNotesGateOnlyTriggersWhenAllReleased() {
    var core = DuetTurnTakingCore()
    _ = core.handle(.noteOn(note: 60, velocity: 90, timestampSeconds: 1.0))
    _ = core.handle(.noteOn(note: 64, velocity: 90, timestampSeconds: 1.1))

    #expect(core.handle(.noteOff(note: 60, timestampSeconds: 1.2)) == .none)
    let decision = core.handle(.noteOff(note: 64, timestampSeconds: 1.3))
    guard case let .scheduleSend(deadlineTimestampSeconds: deadline) = decision else {
        #expect(Bool(false))
        return
    }
    #expect(abs(deadline - 1.9) < 1e-9)
}
