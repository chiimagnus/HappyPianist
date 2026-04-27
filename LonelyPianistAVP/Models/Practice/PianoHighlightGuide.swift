import Foundation

enum PianoHighlightGuideKind: String, Equatable, Hashable {
    case trigger
    case sustain
    case release
    case gap
}

struct PianoHighlightNote: Equatable, Hashable, Identifiable {
    var id: String {
        occurrenceID
    }

    let occurrenceID: String
    let midiNote: Int
    let staff: Int?
    let voice: Int?
    let velocity: UInt8
    let onTick: Int
    let offTick: Int
    let fingeringText: String?
}

struct PianoHighlightGuide: Equatable, Identifiable {
    let id: Int
    let kind: PianoHighlightGuideKind
    let tick: Int
    let durationTicks: Int?
    let practiceStepIndex: Int?
    let activeNotes: [PianoHighlightNote]
    let triggeredNotes: [PianoHighlightNote]
    let releasedMIDINotes: Set<Int>

    var isRestOrGap: Bool {
        kind == .gap || (activeNotes.isEmpty && triggeredNotes.isEmpty)
    }

    var highlightedMIDINotes: Set<Int> {
        var result = Set(activeNotes.map(\.midiNote))
        result.formUnion(triggeredNotes.map(\.midiNote))
        return result
    }

    var fingeringByMIDINote: [Int: String] {
        let items = (activeNotes + triggeredNotes).compactMap { note -> (Int, String)? in
            guard let fingering = note.fingeringText, fingering.isEmpty == false else { return nil }
            return (note.midiNote, fingering)
        }
        return Dictionary(items, uniquingKeysWith: { first, _ in first })
    }
}
