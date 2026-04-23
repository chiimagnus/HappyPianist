import Foundation

final class MusicXMLParserDelegate: NSObject {
    typealias TempoSource = MusicXMLParserDelegateState.TempoSource
    typealias RawTempoEvent = MusicXMLParserDelegateState.RawTempoEvent

    var state = MusicXMLParserDelegateState()

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
