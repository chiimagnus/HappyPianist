import Foundation

struct MusicXMLPartMetadata: Equatable, Sendable {
    let partID: String
    var name: String?
    var abbreviation: String?
    var scoreInstruments: [MusicXMLScoreInstrumentMetadata]
    var midiInstruments: [MusicXMLMIDIInstrumentMetadata]

    init(
        partID: String,
        name: String? = nil,
        abbreviation: String? = nil,
        scoreInstruments: [MusicXMLScoreInstrumentMetadata] = [],
        midiInstruments: [MusicXMLMIDIInstrumentMetadata] = []
    ) {
        self.partID = partID
        self.name = name
        self.abbreviation = abbreviation
        self.scoreInstruments = scoreInstruments
        self.midiInstruments = midiInstruments
    }
}

struct MusicXMLScoreInstrumentMetadata: Equatable, Sendable {
    let id: String
    var name: String?
}

struct MusicXMLMIDIInstrumentMetadata: Equatable, Sendable {
    let id: String
    var channel: Int?
    var program: Int?
    var bank: Int?
}
