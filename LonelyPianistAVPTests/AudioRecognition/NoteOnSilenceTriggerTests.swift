@testable import LonelyPianistAVP
import Testing

@Test
func triggerNeverFiresWithoutAnyNoteOn() {
    var trigger = NoteOnSilenceTrigger()
    #expect(trigger.pollShouldTrigger(atUptime: 10, timeoutSeconds: 2.0) == false)
    #expect(trigger.pollShouldTrigger(atUptime: 100, timeoutSeconds: 2.0) == false)
}

@Test
func triggerFiresOnceAfterTimeout() {
    var trigger = NoteOnSilenceTrigger()
    trigger.recordNoteOn(atUptime: 1.0)

    #expect(trigger.pollShouldTrigger(atUptime: 2.9, timeoutSeconds: 2.0) == false)
    #expect(trigger.pollShouldTrigger(atUptime: 3.0, timeoutSeconds: 2.0) == true)
    #expect(trigger.pollShouldTrigger(atUptime: 100.0, timeoutSeconds: 2.0) == false)
}

@Test
func newNoteOnAllowsAnotherTrigger() {
    var trigger = NoteOnSilenceTrigger()
    trigger.recordNoteOn(atUptime: 1.0)
    #expect(trigger.pollShouldTrigger(atUptime: 3.0, timeoutSeconds: 2.0) == true)

    trigger.recordNoteOn(atUptime: 10.0)
    #expect(trigger.pollShouldTrigger(atUptime: 11.0, timeoutSeconds: 2.0) == false)
    #expect(trigger.pollShouldTrigger(atUptime: 12.0, timeoutSeconds: 2.0) == true)
}

@Test
func resetClearsState() {
    var trigger = NoteOnSilenceTrigger()
    trigger.recordNoteOn(atUptime: 1.0)
    trigger.reset()
    #expect(trigger.pollShouldTrigger(atUptime: 100.0, timeoutSeconds: 2.0) == false)
}
