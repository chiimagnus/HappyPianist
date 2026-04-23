import Foundation

struct MusicXMLParserDelegateState {
    let normalizedTicksPerQuarter = 480

    var scoreVersion: String?

    var notes: [MusicXMLNoteEvent] = []
    var tempoEvents: [MusicXMLTempoEvent] = []
    var soundDirectives: [MusicXMLSoundDirective] = []
    var pedalEvents: [MusicXMLPedalEvent] = []
    var dynamicEvents: [MusicXMLDynamicEvent] = []
    var wedgeEvents: [MusicXMLWedgeEvent] = []
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
    var currentMeasureIndex = 0
    var currentMeasureNumberToken: String?

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
    var isInSound = false
    var currentDirectionStaff: Int?
    var isInDirectionTypeDynamics = false

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
    var noteAttackTicks: Int?
    var noteReleaseTicks: Int?
    var noteIsGrace = false
    var noteType: String?
    var noteDotCount = 0
    var isInTimeModification = false
    var noteTimeModificationActualNotes: Int?
    var noteTimeModificationNormalNotes: Int?
    var noteDynamicsOverrideVelocity: UInt8?

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
    var currentDirectionDynamicStartIndex = 0
    var currentDirectionWedgeStartIndex = 0

    var currentOffsetAppliesToSound = false

    var currentSoundBaseTick = 0
    var currentSoundMeasureStartTick = 0
    var currentSoundTempoStartIndex = 0
    var currentSoundSoundStartIndex = 0
    var currentSoundPedalStartIndex = 0

    var currentDirectionSoundOffsetTempoOverrideTicksByIndex: [Int: Int] = [:]
    var currentDirectionSoundOffsetSoundOverrideTicksByIndex: [Int: Int] = [:]
    var currentDirectionSoundOffsetPedalOverrideTicksByIndex: [Int: Int] = [:]
}
