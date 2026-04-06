import Foundation

final class DefaultSilenceDetectionService: SilenceDetectionServiceProtocol {
    private struct NoteKey: Hashable {
        let note: Int
        let channel: Int
    }

    var timeoutSeconds: TimeInterval

    private let clock: ClockProtocol
    private var lastActivityAt: Date?
    private var openNotes: Set<NoteKey> = []
    private var sustainIsDown = false
    private var hasTriggeredSilence = false

    init(clock: ClockProtocol, timeoutSeconds: TimeInterval = 2.0) {
        self.clock = clock
        self.timeoutSeconds = timeoutSeconds
    }

    func reset() {
        lastActivityAt = nil
        openNotes.removeAll(keepingCapacity: false)
        sustainIsDown = false
        hasTriggeredSilence = false
    }

    func handle(event: MIDIEvent) {
        switch event.type {
        case .noteOn(let note, _):
            openNotes.insert(NoteKey(note: note, channel: event.channel))
            lastActivityAt = event.timestamp
            hasTriggeredSilence = false

        case .noteOff(let note, _):
            openNotes.remove(NoteKey(note: note, channel: event.channel))
            lastActivityAt = event.timestamp
            hasTriggeredSilence = false

        case .controlChange(let controller, let value):
            guard controller == 64 else { return }
            let wasDown = sustainIsDown
            sustainIsDown = value >= 64

            if wasDown, !sustainIsDown {
                // Pedal released: restart the timeout gate.
                lastActivityAt = event.timestamp
                hasTriggeredSilence = false
            }
        }
    }

    func pollSilenceDetected() -> Bool {
        pollSilenceDetected(at: clock.now())
    }

    func pollSilenceDetected(at now: Date) -> Bool {
        guard !hasTriggeredSilence else { return false }
        guard let lastActivityAt else { return false }
        guard now.timeIntervalSince(lastActivityAt) >= timeoutSeconds else { return false }
        guard openNotes.isEmpty else { return false }
        guard !sustainIsDown else { return false }

        hasTriggeredSilence = true
        return true
    }
}

