import Foundation

struct NoteOnSilenceTrigger {
    private var lastNoteOnUptime: TimeInterval?
    private var hasTriggered = false

    mutating func recordNoteOn(atUptime uptime: TimeInterval) {
        lastNoteOnUptime = uptime
        hasTriggered = false
    }

    mutating func pollShouldTrigger(atUptime uptime: TimeInterval, timeoutSeconds: TimeInterval) -> Bool {
        guard hasTriggered == false else { return false }
        guard let lastNoteOnUptime else { return false }
        guard uptime - lastNoteOnUptime >= timeoutSeconds else { return false }
        hasTriggered = true
        return true
    }

    mutating func reset() {
        lastNoteOnUptime = nil
        hasTriggered = false
    }
}

