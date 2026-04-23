import Foundation

struct MusicXMLParserDelegateState {
    let normalizedTicksPerQuarter = 480

    var notes: [MusicXMLNoteEvent] = []
    var tempoEvents: [MusicXMLTempoEvent] = []
    var soundDirectives: [MusicXMLSoundDirective] = []
    var pedalEvents: [MusicXMLPedalEvent] = []
    var measures: [MusicXMLMeasureSpan] = []
    var repeatDirectives: [MusicXMLRepeatDirective] = []
    var endingDirectives: [MusicXMLEndingDirective] = []

    enum TempoSource: Int {
        case metronome = 0
        case sound = 1
    }

    struct RawTempoEvent {
        let partID: String
        let tick: Int
        let quarterBPM: Double
        let source: TempoSource
    }

    var currentPartID = "P1"
    var currentMeasureNumber = 1

    var partDivisions: [String: Int] = [:]
    var partTick: [String: Int] = [:]
    var partMeasureMaxTick: [String: Int] = [:]
    var partLastNonChordStartTick: [String: Int] = [:]

    var currentElement = ""
    var elementText = ""

    var isInAttributes = false
    var isInBackup = false
    var isInForward = false
    var isInDirection = false
    var isInBarline = false

    var isInNote = false
    var noteIsRest = false
    var noteIsChord = false
    var noteStep: String?
    var noteAlter: Int?
    var noteOctave: Int?
    var noteDuration: Int?
    var noteStaff: Int?
    var noteVoice: Int?
    var noteTieStart = false
    var noteTieStop = false

    var isInDirectionTypeMetronome = false
    var metronomeBeatUnit: String?
    var metronomeHasDot = false
    var metronomePerMinute: Double?

    var rawTempoEventsByPart: [String: [RawTempoEvent]] = [:]

    var currentMeasureStartTick = 0
    var currentDirectionOffsetTicks = 0
    var currentDirectionMeasureStartTick = 0
    var currentDirectionTempoStartIndex = 0
    var currentDirectionSoundStartIndex = 0
    var currentDirectionPedalStartIndex = 0
}
