import Foundation

struct MusicXMLScore: Equatable {
    var notes: [MusicXMLNoteEvent]
}

struct MusicXMLNoteEvent: Equatable, Identifiable {
    var id: String { "\(partID)-\(measureNumber)-\(tick)-\(midiNote ?? -1)-\(durationTicks)-\(isRest)-\(isChord)" }
    let partID: String
    let measureNumber: Int
    let tick: Int
    let durationTicks: Int
    let midiNote: Int?
    let isRest: Bool
    let isChord: Bool
    let staff: Int?
    let voice: Int?
}
