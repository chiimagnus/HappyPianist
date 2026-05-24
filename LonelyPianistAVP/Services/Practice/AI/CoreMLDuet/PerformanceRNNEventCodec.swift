import Foundation
import ImprovProtocol

/// Performance RNN event codec (Magenta / note-seq compatible).
///
/// Vocabulary (numClasses=388):
/// - NOTE_ON(pitch 0..127) -> 0..127
/// - NOTE_OFF(pitch 0..127) -> 128..255
/// - TIME_SHIFT(steps 1..100) -> 256..355
/// - VELOCITY(bin 1..32) -> 356..387
struct PerformanceRNNEventCodec: Sendable {
    static let numClasses = 388
    static let stepsPerSecond = 100
    static let numVelocityBins = 32
    static let velocityBinSize = 4

    init() {}

    func encode(notes: [ImprovDialogueNote]) -> [Int] {
        let edgeEvents = collectNoteEdgeEvents(notes: notes)
        guard edgeEvents.isEmpty == false else { return [] }

        var currentStep = 0
        var currentVelocityBin: Int?
        var eventIDs: [Int] = []
        eventIDs.reserveCapacity(edgeEvents.count * 2)

        for event in edgeEvents {
            emitTimeShiftIfNeeded(from: currentStep, to: event.step, eventIDs: &eventIDs)
            currentStep = event.step

            switch event.kind {
            case .noteOff:
                eventIDs.append(Self.noteOffEventID(pitch: event.pitch))
            case let .noteOn(velocityBin):
                if currentVelocityBin != velocityBin {
                    eventIDs.append(Self.velocityEventID(bin: velocityBin))
                    currentVelocityBin = velocityBin
                }
                eventIDs.append(Self.noteOnEventID(pitch: event.pitch))
            }
        }

        return eventIDs
    }

    func decode(eventIDs: [Int], promptEndTimeSeconds: Double) -> [ImprovDialogueNote] {
        var currentStep = 0
        var currentVelocity = 90

        struct OpenNote: Sendable {
            let startStep: Int
            let velocity: Int
        }
        var openNotes: [Int: OpenNote] = [:]

        var decoded: [ImprovDialogueNote] = []
        decoded.reserveCapacity(eventIDs.count / 2)

        func closeNote(pitch: Int, endStep: Int) {
            guard let open = openNotes.removeValue(forKey: pitch) else { return }
            appendNote(pitch: pitch, velocity: open.velocity, startStep: open.startStep, endStep: endStep)
        }

        func appendNote(pitch: Int, velocity: Int, startStep: Int, endStep: Int) {
            let clampedPitch = max(21, min(108, pitch))
            let clampedVelocity = max(1, min(127, velocity))

            let absStart = Double(startStep) / Double(Self.stepsPerSecond)
            let absEnd = Double(max(endStep, startStep)) / Double(Self.stepsPerSecond)

            let clippedStart = max(absStart, promptEndTimeSeconds)
            let clippedEnd = absEnd
            guard clippedEnd > clippedStart else { return }

            let time = clippedStart - promptEndTimeSeconds
            let duration = max(0.01, clippedEnd - clippedStart)
            decoded.append(ImprovDialogueNote(note: clampedPitch, velocity: clampedVelocity, time: time, duration: duration))
        }

        for eventID in eventIDs {
            switch eventID {
            case 0 ... 127: // NOTE_ON
                let pitch = eventID
                if openNotes[pitch] != nil {
                    closeNote(pitch: pitch, endStep: currentStep)
                }
                openNotes[pitch] = OpenNote(startStep: currentStep, velocity: currentVelocity)

            case 128 ... 255: // NOTE_OFF
                let pitch = eventID - 128
                closeNote(pitch: pitch, endStep: currentStep)

            case 256 ... 355: // TIME_SHIFT
                currentStep += (eventID - 255)

            case 356 ... 387: // VELOCITY
                let bin = eventID - 355
                currentVelocity = Self.binToVelocity(bin)

            default:
                continue
            }
        }

        // Settle remaining open notes with a max duration cap to avoid infinite sustain.
        let maxDurationSteps = 5 * Self.stepsPerSecond
        for (pitch, open) in openNotes {
            let endStep = max(open.startStep + 1, min(open.startStep + maxDurationSteps, currentStep))
            appendNote(pitch: pitch, velocity: open.velocity, startStep: open.startStep, endStep: endStep)
        }

        return decoded.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }
    }

    static func velocityToBin(_ velocity: Int) -> Int {
        let clampedVelocity = max(1, min(127, velocity))
        let zeroBased = (clampedVelocity - 1) / velocityBinSize
        return max(1, min(numVelocityBins, zeroBased + 1))
    }

    static func binToVelocity(_ bin: Int) -> Int {
        let clampedBin = max(1, min(numVelocityBins, bin))
        return 1 + (clampedBin - 1) * velocityBinSize
    }

    private enum NoteEdgeKind: Sendable, Hashable {
        case noteOff
        case noteOn(velocityBin: Int)
    }

    private struct NoteEdgeEvent: Sendable, Hashable {
        let step: Int
        let pitch: Int
        let kind: NoteEdgeKind
    }

    private func collectNoteEdgeEvents(notes: [ImprovDialogueNote]) -> [NoteEdgeEvent] {
        var events: [NoteEdgeEvent] = []
        events.reserveCapacity(notes.count * 2)

        for note in notes {
            let pitch = max(0, min(127, note.note))
            let velocityBin = Self.velocityToBin(note.velocity)

            let startStep = Self.quantizedStep(seconds: note.time)
            let endStep = Self.quantizedStep(seconds: note.time + note.duration)

            events.append(.init(step: startStep, pitch: pitch, kind: .noteOn(velocityBin: velocityBin)))
            events.append(.init(step: endStep, pitch: pitch, kind: .noteOff))
        }

        // Ordering rules (note-seq / MIDI convention):
        // - Primary: step ascending
        // - Same step: NOTE_OFF before NOTE_ON (stable retrigger)
        // - Same kind: pitch ascending (stable chord encoding)
        events.sort { lhs, rhs in
            if lhs.step != rhs.step { return lhs.step < rhs.step }
            let lhsPriority = kindPriority(lhs.kind)
            let rhsPriority = kindPriority(rhs.kind)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            return lhs.pitch < rhs.pitch
        }

        return events
    }

    private func kindPriority(_ kind: NoteEdgeKind) -> Int {
        switch kind {
        case .noteOff:
            return 0
        case .noteOn:
            return 1
        }
    }

    private func emitTimeShiftIfNeeded(from currentStep: Int, to targetStep: Int, eventIDs: inout [Int]) {
        guard targetStep > currentStep else { return }
        var remaining = targetStep - currentStep
        while remaining > 0 {
            let chunk = min(remaining, 100)
            eventIDs.append(Self.timeShiftEventID(steps: chunk))
            remaining -= chunk
        }
    }

    private static func quantizedStep(seconds: Double) -> Int {
        let clampedSeconds = max(0, seconds)
        return Int(clampedSeconds * Double(stepsPerSecond) + 0.5)
    }

    private static func noteOnEventID(pitch: Int) -> Int {
        max(0, min(127, pitch))
    }

    private static func noteOffEventID(pitch: Int) -> Int {
        128 + max(0, min(127, pitch))
    }

    private static func timeShiftEventID(steps: Int) -> Int {
        255 + max(1, min(100, steps))
    }

    private static func velocityEventID(bin: Int) -> Int {
        355 + max(1, min(numVelocityBins, bin))
    }
}
