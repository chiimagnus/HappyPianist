import Foundation

struct MusicXMLSoundEventStartIndices {
    var tempo = 0
    var sound = 0
    var pedal = 0
}

struct MusicXMLParserDelegateState {

    struct PendingPerformanceNotation {
        let sourceOrdinal: Int
        let kind: MusicXMLPerformanceNotationKind
        let rawElementToken: String
        let typeToken: String?
        let numberToken: String?
        let placementToken: String?
        var textToken: String?
        let attributes: [String: String]
    }

    struct PendingTie {
        let sourceOrdinal: Int
        let sourceElement: MusicXMLTieSourceElement
        let typeToken: String?
        let numberToken: String?
        let placementToken: String?
    }

    struct PendingSlur {
        let sourceOrdinal: Int
        let typeToken: String?
        let numberToken: String?
        let placementToken: String?
    }

    struct PendingTuplet {
        let sourceOrdinal: Int
        let typeToken: String?
        let numberToken: String?
        let bracketToken: String?
        let placementToken: String?
    }

    struct PendingFingering {
        let sourceOrdinal: Int
        let substitution: MusicXMLFingeringOption
        let alternate: MusicXMLFingeringOption
        let placementToken: String?
        let hand: MusicXMLFingeringHand
        var text: String?
    }

    let normalizedTicksPerQuarter = 480
    let directionOffsetResolver = MusicXMLDirectionOffsetResolver(ticksPerQuarter: 480)

    var scoreVersion: String?
    var partMetadataByID: [String: MusicXMLPartMetadata] = [:]
    var partMetadataOrder: [String] = []
    var bodyPartIDs: Set<String> = []
    var metadataError: MusicXMLParserError?
    var isInPartList = false
    var currentScorePartMetadata: MusicXMLPartMetadata?
    var currentScoreInstrumentMetadata: MusicXMLScoreInstrumentMetadata?
    var currentMIDIInstrumentMetadata: MusicXMLMIDIInstrumentMetadata?

    var notes: [MusicXMLNoteEvent] = []
    var tempoEvents: [MusicXMLTempoEvent] = []
    var soundDirectives: [MusicXMLSoundDirective] = []
    var pedalEvents: [MusicXMLPedalEvent] = []
    var dynamicEvents: [MusicXMLDynamicEvent] = []
    var wedgeEvents: [MusicXMLWedgeEvent] = []
    var fermataEvents: [MusicXMLFermataEvent] = []
    var timeSignatureEvents: [MusicXMLTimeSignatureEvent] = []
    var keySignatureEvents: [MusicXMLKeySignatureEvent] = []
    var clefEvents: [MusicXMLClefEvent] = []
    var transposeEvents: [MusicXMLTransposeEvent] = []
    var octaveShiftEvents: [MusicXMLOctaveShiftEvent] = []
    var wordsEvents: [MusicXMLWordsEvent] = []
    var measures: [MusicXMLMeasureSpan] = []
    var repeatDirectives: [MusicXMLRepeatDirective] = []
    var endingDirectives: [MusicXMLEndingDirective] = []

    enum TempoSource: Int {
        case metronome = 0
        case sound = 1
    }

    struct RawTempoEvent {
        let sourceID: MusicXMLDirectionSourceID?
        let partID: String
        let tick: Int
        let quarterBPM: Double
        let source: TempoSource
        let staff: Int?
        let placementToken: String?
    }

    var currentPartID = "P1"
    var currentMeasureNumber = 1
    var currentMeasureIndex = 0
    var currentMeasureNumberToken: String?
    var currentSourceNoteOrdinal = 0
    var currentDirectionSourceOrdinal = 0
    var currentDirectionSourceID: MusicXMLDirectionSourceID?
    var currentSoundSourceID: MusicXMLDirectionSourceID?

    var partDivisions: [String: Int] = [:]
    var partTick: [String: Int] = [:]
    var partMeasureMaxTick: [String: Int] = [:]
    var partLastNonChordStartTick: [String: Int] = [:]

    var currentElement = ""
    var elementText = ""

    var isInAttributes = false
    var isInTime = false
    var timeBeatGroups: [[Int]] = []
    var timeBeatTypes: [Int] = []
    var timeSymbolToken: String?
    var timeNumberToken: String?
    var timeIsSenzaMisura = false
    var isInKey = false
    var keyFifths: Int?
    var keyModeToken: String?
    var keyNumberToken: String?
    var isInClef = false
    var clefSignToken: String?
    var clefLine: Int?
    var clefOctaveChange: Int?
    var clefNumberToken: String?
    var isInTranspose = false
    var transposeDiatonic: Int?
    var transposeChromatic: Int?
    var transposeOctaveChange: Int?
    var transposeIsDouble = false
    var isInBackup = false
    var isInForward = false
    var isInDirection = false
    var isInBarline = false
    var isInSound = false
    var currentDirectionStaff: Int?
    var currentDirectionPlacementToken: String?
    var isInDirectionTypeDynamics = false

    var isInNote = false
    var noteIsRest = false
    var noteIsMeasureRest = false
    var noteIsPrintObjectVisible = true
    var noteIsChord = false
    var noteStep: String?
    var noteAlter: Double?
    var noteAccidentalToken: String?
    var noteOctave: Int?
    var noteDuration: Int?
    var noteStaff: Int?
    var noteVoice: Int?
    var noteTies: [PendingTie] = []
    var noteSlurs: [PendingSlur] = []
    var noteTuplets: [PendingTuplet] = []
    var nextNoteNotationSourceOrdinal = 0
    var noteStem: MusicXMLStem = .unspecified
    var noteBeams: [MusicXMLBeam] = []
    var currentBeamAttributes: [String: String] = [:]
    var noteAttackTicks: Int?
    var noteReleaseTicks: Int?
    var noteIsGrace = false
    var noteGraceSlash = false
    var noteGraceStealTimePrevious: Double?
    var noteGraceStealTimeFollowing: Double?
    var noteGraceMakeTimeTicks: Int?
    var noteType: String?
    var noteDotCount = 0
    var isInTimeModification = false
    var noteTimeModificationActualNotes: Int?
    var noteTimeModificationNormalNotes: Int?
    var noteTimeModificationNormalType: String?
    var noteTimeModificationNormalDotCount = 0
    var noteDynamicsOverrideVelocity: UInt8?
    var isInNoteArticulations = false
    var noteArticulations: Set<MusicXMLArticulation> = []
    var noteHasFermata = false
    var noteFermataPlacementToken: String?
    var noteArpeggiate: MusicXMLArpeggiate?
    var notePerformanceNotations: [PendingPerformanceNotation] = []
    var currentPerformanceNotationIndexByElement: [String: Int] = [:]
    var isInNoteNotations = false
    var isInNoteOrnaments = false
    var noteFingerings: [PendingFingering] = []
    var currentFingeringIndex: Int?
    var isInTechnical = false

    var isInDirectionTypeMetronome = false
    var metronomeBeatUnit: String?
    var metronomeHasDot = false
    var metronomePerMinute: Double?

    var rawTempoEventsByPart: [String: [RawTempoEvent]] = [:]

    var currentMeasureStartTick = 0
    var currentDirectionOffsetTicks = 0
    var currentDirectionOffsetAffectsSound = false

    var currentSoundBaseTick = 0
    var currentSoundEventStartIndices = MusicXMLSoundEventStartIndices()
}
