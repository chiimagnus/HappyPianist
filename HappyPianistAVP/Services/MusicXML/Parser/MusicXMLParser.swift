import Foundation

enum MusicXMLParserError: Error, Equatable {
    case parseFailed(line: Int?, column: Int?, reason: String)
    case invalidPartMetadata(reason: String)
}

protocol MusicXMLParserProtocol: Sendable {
    func parse(data: Data) throws -> MusicXMLScore
    func parse(fileURL: URL) throws -> MusicXMLScore
}

struct MusicXMLParser: MusicXMLParserProtocol {
    private let isCancelled: @Sendable () -> Bool

    init(isCancelled: @escaping @Sendable () -> Bool = {
        withUnsafeCurrentTask { $0?.isCancelled == true }
    }) {
        self.isCancelled = isCancelled
    }

    func parse(fileURL: URL) throws -> MusicXMLScore {
        let data: Data = if fileURL.pathExtension.lowercased() == "mxl" {
            try MXLReader().readScoreXMLData(from: fileURL)
        } else {
            try Data(contentsOf: fileURL)
        }
        return try parse(data: data)
    }

    func parse(data: Data) throws -> MusicXMLScore {
        try Task.checkCancellation()
        let normalizedData = try MusicXMLTimewiseConverter().convertToPartwiseIfNeeded(data: data)
        try Task.checkCancellation()
        let delegate = MusicXMLParserDelegate(isCancelled: isCancelled)
        let parser = XMLParser(data: normalizedData)
        parser.delegate = delegate
        guard parser.parse() else {
            if delegate.wasCancelled {
                throw CancellationError()
            }
            throw MusicXMLParserError.parseFailed(
                line: parser.lineNumber > 0 ? parser.lineNumber : nil,
                column: parser.columnNumber > 0 ? parser.columnNumber : nil,
                reason: parser.parserError.map(PracticePreparationErrorDetails.safeErrorSummary) ?? "XMLParser returned no error details."
            )
        }
        try Task.checkCancellation()
        if let metadataError = delegate.metadataError {
            throw metadataError
        }
        return MusicXMLScore(
            scoreVersion: delegate.scoreVersion,
            partMetadata: delegate.partMetadata,
            notes: delegate.notes,
            tempoEvents: delegate.tempoEvents,
            soundDirectives: delegate.soundDirectives,
            pedalEvents: delegate.pedalEvents,
            dynamicEvents: delegate.dynamicEvents,
            wedgeEvents: delegate.wedgeEvents,
            fermataEvents: delegate.fermataEvents,
            timeSignatureEvents: delegate.timeSignatureEvents,
            keySignatureEvents: delegate.keySignatureEvents,
            clefEvents: delegate.clefEvents,
            transposeEvents: delegate.transposeEvents,
            octaveShiftEvents: delegate.octaveShiftEvents,
            wordsEvents: delegate.wordsEvents,
            measures: delegate.measures,
            repeatDirectives: delegate.repeatDirectives,
            endingDirectives: delegate.endingDirectives
        )
    }
}
