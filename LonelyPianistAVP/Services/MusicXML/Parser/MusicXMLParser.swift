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
        let data: Data = if fileURL.pathExtension.lowercased() == "mxl" {
            try MXLReader().readScoreXMLData(from: fileURL)
        } else {
            try Data(contentsOf: fileURL)
        }
        return try parse(data: data)
    }

    func parse(data: Data) throws -> MusicXMLScore {
        let normalizedData = try MusicXMLTimewiseConverter().convertToPartwiseIfNeeded(data: data)
        let delegate = MusicXMLParserDelegate()
        let parser = XMLParser(data: normalizedData)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MusicXMLParserError.parseFailed
        }
        return MusicXMLScore(
            scoreVersion: delegate.scoreVersion,
            notes: delegate.notes,
            tempoEvents: delegate.tempoEvents,
            soundDirectives: delegate.soundDirectives,
            pedalEvents: delegate.pedalEvents,
            dynamicEvents: delegate.dynamicEvents,
            measures: delegate.measures,
            repeatDirectives: delegate.repeatDirectives,
            endingDirectives: delegate.endingDirectives
        )
    }
}
