import Foundation

enum MusicXMLParserError: Error, Equatable {
    case invalidData
    case parseFailed
}

protocol MusicXMLParserProtocol {
    func parse(data: Data) throws -> MusicXMLScore
    func parse(fileURL: URL) throws -> MusicXMLScore
}

struct MusicXMLParser: MusicXMLParserProtocol {
    func parse(fileURL: URL) throws -> MusicXMLScore {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
    }

    func parse(data: Data) throws -> MusicXMLScore {
        let delegate = MusicXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MusicXMLParserError.parseFailed
        }
        return MusicXMLScore(
            notes: delegate.notes,
            tempoEvents: delegate.tempoEvents,
            soundDirectives: delegate.soundDirectives,
            pedalEvents: delegate.pedalEvents,
            measures: delegate.measures,
            repeatDirectives: delegate.repeatDirectives,
            endingDirectives: delegate.endingDirectives
        )
    }
}

