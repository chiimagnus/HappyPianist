import Foundation

final class MusicXMLParserDelegate: NSObject {
    typealias TempoSource = MusicXMLParserDelegateState.TempoSource
    typealias RawTempoEvent = MusicXMLParserDelegateState.RawTempoEvent

    var state = MusicXMLParserDelegateState()
    private let isCancelled: @Sendable () -> Bool
    private(set) var wasCancelled = false

    init(isCancelled: @escaping @Sendable () -> Bool) {
        self.isCancelled = isCancelled
        super.init()
    }

    func abortIfCancelled(_ parser: XMLParser) -> Bool {
        guard isCancelled() else { return false }
        wasCancelled = true
        parser.abortParsing()
        return true
    }

    var scoreVersion: String? {
        state.scoreVersion
    }

    var partMetadata: [MusicXMLPartMetadata] {
        state.partMetadataOrder.compactMap { state.partMetadataByID[$0] }
    }

    var metadataError: MusicXMLParserError? {
        state.metadataError
    }

    var notes: [MusicXMLNoteEvent] {
        state.notes
    }

    var tempoEvents: [MusicXMLTempoEvent] {
        state.tempoEvents
    }

    var soundDirectives: [MusicXMLSoundDirective] {
        state.soundDirectives
    }

    var pedalEvents: [MusicXMLPedalEvent] {
        state.pedalEvents
    }

    var dynamicEvents: [MusicXMLDynamicEvent] {
        state.dynamicEvents
    }

    var wedgeEvents: [MusicXMLWedgeEvent] {
        state.wedgeEvents
    }

    var fermataEvents: [MusicXMLFermataEvent] {
        state.fermataEvents
    }

    var timeSignatureEvents: [MusicXMLTimeSignatureEvent] {
        state.timeSignatureEvents
    }

    var keySignatureEvents: [MusicXMLKeySignatureEvent] {
        state.keySignatureEvents
    }

    var clefEvents: [MusicXMLClefEvent] {
        state.clefEvents
    }

    var transposeEvents: [MusicXMLTransposeEvent] {
        state.transposeEvents
    }

    var octaveShiftEvents: [MusicXMLOctaveShiftEvent] {
        state.octaveShiftEvents
    }

    var wordsEvents: [MusicXMLWordsEvent] {
        state.wordsEvents
    }

    var measures: [MusicXMLMeasureSpan] {
        state.measures
    }

    var repeatDirectives: [MusicXMLRepeatDirective] {
        state.repeatDirectives
    }

    var endingDirectives: [MusicXMLEndingDirective] {
        state.endingDirectives
    }
}
