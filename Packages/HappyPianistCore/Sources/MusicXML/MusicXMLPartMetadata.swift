import Foundation


public struct MusicXMLPartMetadata: Equatable, Sendable {
    public let partID: String
    public var name: String?
    public var abbreviation: String?
    public var scoreInstruments: [MusicXMLScoreInstrumentMetadata]
    public var midiInstruments: [MusicXMLMIDIInstrumentMetadata]

    public init(
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

public struct MusicXMLScoreInstrumentMetadata: Equatable, Sendable {
    public let id: String
    public var name: String?
}

public struct MusicXMLMIDIInstrumentMetadata: Equatable, Sendable {
    public let id: String
    public var channel: Int?
    public var program: Int?
    public var bank: Int?
}
