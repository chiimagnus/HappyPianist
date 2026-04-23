import Foundation

final class MusicXMLParserDelegate: NSObject {
    typealias TempoSource = MusicXMLParserDelegateState.TempoSource
    typealias RawTempoEvent = MusicXMLParserDelegateState.RawTempoEvent

    var state = MusicXMLParserDelegateState()

    var scoreVersion: String? {
        state.scoreVersion
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

    var slurEvents: [MusicXMLSlurEvent] {
        state.slurEvents
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
