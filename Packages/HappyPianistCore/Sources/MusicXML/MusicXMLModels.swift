import Foundation


public struct MusicXMLScore: Equatable, Sendable {
    public var scoreVersion: String?
    public var partMetadata: [MusicXMLPartMetadata] = []
    public var logicalInstruments: [MusicXMLLogicalInstrument] = []
    public var notes: [MusicXMLNoteEvent]
    public var tempoEvents: [MusicXMLTempoEvent] = []
    public var soundDirectives: [MusicXMLSoundDirective] = []
    public var pedalEvents: [MusicXMLPedalEvent] = []
    public var dynamicEvents: [MusicXMLDynamicEvent] = []
    public var wedgeEvents: [MusicXMLWedgeEvent] = []
    public var fermataEvents: [MusicXMLFermataEvent] = []
    public var timeSignatureEvents: [MusicXMLTimeSignatureEvent] = []
    public var keySignatureEvents: [MusicXMLKeySignatureEvent] = []
    public var clefEvents: [MusicXMLClefEvent] = []
    public var transposeEvents: [MusicXMLTransposeEvent] = []
    public var octaveShiftEvents: [MusicXMLOctaveShiftEvent] = []
    public var wordsEvents: [MusicXMLWordsEvent] = []
    public var measures: [MusicXMLMeasureSpan] = []
    public var repeatDirectives: [MusicXMLRepeatDirective] = []
    public var endingDirectives: [MusicXMLEndingDirective] = []
}

public struct MusicXMLEventScope: Equatable, Sendable {
    public let partID: String
    public let staff: Int?
    public let voice: Int?
}

public enum MusicXMLDynamicEventSource: Equatable, Sendable {
    case directionDynamics
    case soundDynamicsAttribute
}

public struct MusicXMLDynamicEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let tick: Int
    public let velocity: UInt8
    public let scope: MusicXMLEventScope
    public let source: MusicXMLDynamicEventSource
    public let markToken: String?
    public let placementToken: String?

    public init(
        sourceID: MusicXMLDirectionSourceID? = nil,
        performedOccurrenceIndex: Int = 0,
        tick: Int,
        velocity: UInt8,
        scope: MusicXMLEventScope,
        source: MusicXMLDynamicEventSource,
        markToken: String? = nil,
        placementToken: String? = nil
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.velocity = velocity
        self.scope = scope
        self.source = source
        self.markToken = markToken
        self.placementToken = placementToken
    }
}

public enum MusicXMLWedgeKind: Equatable, Sendable {
    case crescendoStart
    case diminuendoStart
    case stop
}

public struct MusicXMLWedgeEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let tick: Int
    public let kind: MusicXMLWedgeKind
    public let numberToken: String?
    public let scope: MusicXMLEventScope
}

public struct MusicXMLWedgePairKey: Equatable, Hashable, Sendable {
    public let partID: String
    public let staff: Int?
    public let voice: Int?
    public let numberToken: String
}

extension MusicXMLWedgeEvent {
    public var normalizedNumberToken: String {
        guard let token = numberToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              token.isEmpty == false
        else {
            return "1"
        }
        return token
    }

    public var pairKey: MusicXMLWedgePairKey {
        MusicXMLWedgePairKey(
            partID: scope.partID,
            staff: scope.staff,
            voice: scope.voice,
            numberToken: normalizedNumberToken
        )
    }
}

public struct MusicXMLWedgeApproximation: Equatable, Sendable {
    public let sourceID: MusicXMLDirectionSourceID?
    public let reason: String
}

public enum MusicXMLFermataEventSource: Equatable, Sendable {
    case noteNotations
    case directionType
}

public struct MusicXMLFermataEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let tick: Int
    public let scope: MusicXMLEventScope
    public let source: MusicXMLFermataEventSource
    public let placementToken: String?

    public init(
        sourceID: MusicXMLDirectionSourceID? = nil,
        performedOccurrenceIndex: Int = 0,
        tick: Int,
        scope: MusicXMLEventScope,
        source: MusicXMLFermataEventSource,
        placementToken: String? = nil
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.scope = scope
        self.source = source
        self.placementToken = placementToken
    }
}

public enum MusicXMLArpeggiateDirection: String, Codable, Equatable, Hashable, Sendable {
    case up
    case down
}

public struct MusicXMLArpeggiate: Equatable, Hashable, Sendable {
    public let numberToken: String?
    public let directionToken: String?

    public var normalizedNumberToken: String {
        guard let trimmed = numberToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return "1"
        }
        return trimmed
    }

    public var direction: MusicXMLArpeggiateDirection? {
        guard let token = directionToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        return MusicXMLArpeggiateDirection(rawValue: token)
    }
}

public struct MusicXMLTimeSignatureEvent: Equatable, Identifiable, Sendable {
    public var id: String {
        "\(tick)-\(meter.displayText)-\(scope.partID)"
    }

    public let tick: Int
    public let meter: MusicXMLMeter
    public let scope: MusicXMLEventScope

    public var beats: Int {
        meter.totalBeats
    }

    public var beatType: Int {
        meter.primaryBeatType
    }

    public init(tick: Int, meter: MusicXMLMeter, scope: MusicXMLEventScope) {
        self.tick = tick
        self.meter = meter
        self.scope = scope
    }

    public init(tick: Int, beats: Int, beatType: Int, scope: MusicXMLEventScope) {
        self.init(
            tick: tick,
            meter: MusicXMLMeter(
                components: [.init(beatGroups: [beats], beatType: beatType)],
                symbolToken: nil,
                isSenzaMisura: false,
                approximation: nil
            ),
            scope: scope
        )
    }
}

public struct MusicXMLKeySignatureEvent: Equatable, Identifiable, Sendable {
    public var id: String {
        "\(tick)-\(fifths)-\(modeToken ?? "")-\(scope.partID)"
    }

    public let tick: Int
    public let fifths: Int
    public let modeToken: String?
    public let scope: MusicXMLEventScope
}

public struct MusicXMLClefEvent: Equatable, Identifiable, Sendable {
    public var id: String {
        "\(tick)-\(signToken ?? "")-\(line ?? -1)-\(octaveChange ?? 0)-\(numberToken ?? "")-\(scope.partID)"
    }

    public let tick: Int
    public let signToken: String?
    public let line: Int?
    public let octaveChange: Int?
    public let numberToken: String?
    public let scope: MusicXMLEventScope
}

public struct MusicXMLWordsEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let tick: Int
    public let text: String
    public let scope: MusicXMLEventScope
    public let placementToken: String?

    public init(
        sourceID: MusicXMLDirectionSourceID? = nil,
        performedOccurrenceIndex: Int = 0,
        tick: Int,
        text: String,
        scope: MusicXMLEventScope,
        placementToken: String? = nil
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.text = text
        self.scope = scope
        self.placementToken = placementToken
    }
}

public enum MusicXMLArticulation: String, CaseIterable, Equatable, Hashable, Sendable {
    case staccato
    case accent
    case tenuto
    case marcato
    case staccatissimo
    case detachedLegato = "detached-legato"
}

public struct MusicXMLTempoEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let tick: Int
    public let quarterBPM: Double
    public let scope: MusicXMLEventScope
    public let placementToken: String?
    public let notationBeatUnitToken: String?
    public let notationBeatUnitDotCount: Int
    public let notationPerMinute: Double?

    public var hasVisibleNotationMark: Bool {
        notationBeatUnitToken != nil && notationPerMinute != nil
    }

    public init(
        sourceID: MusicXMLDirectionSourceID? = nil,
        performedOccurrenceIndex: Int = 0,
        tick: Int,
        quarterBPM: Double,
        scope: MusicXMLEventScope,
        placementToken: String? = nil,
        notationBeatUnitToken: String? = nil,
        notationBeatUnitDotCount: Int = 0,
        notationPerMinute: Double? = nil
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.tick = tick
        self.quarterBPM = quarterBPM
        self.scope = scope
        self.placementToken = placementToken
        self.notationBeatUnitToken = notationBeatUnitToken
        self.notationBeatUnitDotCount = max(0, notationBeatUnitDotCount)
        self.notationPerMinute = notationPerMinute
    }
}

public struct MusicXMLSoundDirective: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let partID: String
    public let measureNumber: Int
    public let tick: Int
    public let segno: String?
    public let coda: String?
    public let tocoda: String?
    public let dalsegno: String?
    public let dacapo: String?
    public let timeOnlyPasses: [Int]?
}

public enum MusicXMLPedalEventKind: String, Equatable, Sendable {
    case start
    case stop
    case change
    case `continue`
}

public struct MusicXMLPedalEvent: Equatable, Sendable {
    public var sourceID: MusicXMLDirectionSourceID?
    public var performedOccurrenceIndex: Int = 0
    public var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let partID: String
    public let measureNumber: Int
    public let tick: Int
    public let kind: MusicXMLPedalEventKind
    public var controller: MusicXMLPedalController = .damper
    public let value: MusicXMLControllerValue?
    public let timeOnlyPasses: [Int]?
    public let staff: Int?
    public let placementToken: String?

    public init(
        sourceID: MusicXMLDirectionSourceID? = nil,
        performedOccurrenceIndex: Int = 0,
        partID: String,
        measureNumber: Int,
        tick: Int,
        kind: MusicXMLPedalEventKind,
        controller: MusicXMLPedalController = .damper,
        value: MusicXMLControllerValue?,
        timeOnlyPasses: [Int]?,
        staff: Int? = nil,
        placementToken: String? = nil
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = performedOccurrenceIndex
        self.partID = partID
        self.measureNumber = measureNumber
        self.tick = tick
        self.kind = kind
        self.controller = controller
        self.value = value
        self.timeOnlyPasses = timeOnlyPasses
        self.staff = staff
        self.placementToken = placementToken
    }
}

public struct MusicXMLMeasureSpan: Equatable, Identifiable, Sendable {
    public var id: String {
        "\(partID)-\(sourceMeasureIndex)-\(occurrenceIndex)-\(startTick)-\(endTick)"
    }

    public let partID: String
    public let measureNumber: Int
    public let sourceMeasureIndex: Int
    public let sourceMeasureNumberToken: String?
    public let occurrenceIndex: Int
    public let startTick: Int
    public let endTick: Int

    public var sourceMeasureID: PracticeSourceMeasureID {
        PracticeSourceMeasureID(
            partID: partID,
            sourceMeasureIndex: sourceMeasureIndex,
            sourceNumberToken: sourceMeasureNumberToken
        )
    }

    public var occurrenceID: PracticeMeasureOccurrenceID {
        PracticeMeasureOccurrenceID(
            sourceMeasureID: sourceMeasureID,
            occurrenceIndex: occurrenceIndex
        )
    }
}

public enum MusicXMLRepeatDirection: String, Equatable, Sendable {
    case forward
    case backward
}

public struct MusicXMLRepeatDirective: Equatable, Sendable {
    public let partID: String
    public let measureNumber: Int
    public let direction: MusicXMLRepeatDirection
    public let times: Int?

    public init(
        partID: String,
        measureNumber: Int,
        direction: MusicXMLRepeatDirection,
        times: Int? = nil
    ) {
        self.partID = partID
        self.measureNumber = measureNumber
        self.direction = direction
        self.times = times
    }
}

public enum MusicXMLEndingType: String, Equatable, Sendable {
    case start
    case stop
    case discontinue
}

public struct MusicXMLEndingDirective: Equatable, Sendable {
    public let partID: String
    public let measureNumber: Int
    public let number: String
    public let type: MusicXMLEndingType
}

public enum MusicXMLTieSourceElement: String, Equatable, Sendable {
    case sound = "tie"
    case notation = "tied"
}

public struct MusicXMLTie: Equatable, Sendable {
    public let sourceID: MusicXMLPerformanceNotationSourceID?
    public let sourceElement: MusicXMLTieSourceElement
    public let typeToken: String?
    public let numberToken: String?
    public let placementToken: String?
}

public struct MusicXMLSlur: Equatable, Sendable {
    public let sourceID: MusicXMLPerformanceNotationSourceID?
    public let typeToken: String?
    public let numberToken: String?
    public let placementToken: String?
}

public struct MusicXMLTuplet: Equatable, Sendable {
    public let sourceID: MusicXMLPerformanceNotationSourceID?
    public let typeToken: String?
    public let numberToken: String?
    public let bracketToken: String?
    public let placementToken: String?
}

public enum MusicXMLStem: Equatable, Sendable {
    case unspecified
    case up
    case down
    case none
    case double
    case unsupported(sourceToken: String)

    public init(sourceToken: String?) {
        let token = sourceToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        self = switch token {
        case "": .unspecified
        case "up": .up
        case "down": .down
        case "none": .none
        case "double": .double
        default: .unsupported(sourceToken: token)
        }
    }
}

public enum MusicXMLBeamValue: Equatable, Sendable {
    case begin
    case `continue`
    case end
    case forwardHook
    case backwardHook
    case unsupported(sourceToken: String)

    public init(sourceToken: String) {
        let token = sourceToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = switch token {
        case "begin": .begin
        case "continue": .continue
        case "end": .end
        case "forward hook": .forwardHook
        case "backward hook": .backwardHook
        default: .unsupported(sourceToken: token)
        }
    }
}

public struct MusicXMLBeam: Equatable, Sendable {
    public let numberToken: String?
    public let value: MusicXMLBeamValue
    public let repeaterToken: String?
    public let fanToken: String?
}

public struct MusicXMLNoteEvent: Equatable, Identifiable, Sendable {
    public var id: MusicXMLPerformedNoteID? {
        performedID
    }

    public var performedID: MusicXMLPerformedNoteID? {
        sourceID.map { MusicXMLPerformedNoteID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    public let sourceID: MusicXMLSourceNoteID?
    public let performedOccurrenceIndex: Int
    public let partID: String
    public let measureNumber: Int
    public let tick: Int
    public let durationTicks: Int
    public let hasExplicitDuration: Bool
    public let writtenPitch: MusicXMLWrittenPitch?
    public let writtenRhythm: MusicXMLWrittenRhythm?
    public let noteheadToken: String?
    public let midiNote: Int?
    public let isRest: Bool
    public let isMeasureRest: Bool
    public let isPrintObjectVisible: Bool
    public let isChord: Bool
    public let isGrace: Bool
    public let graceSlash: Bool
    public let graceStealTimePrevious: Double?
    public let graceStealTimeFollowing: Double?
    public let graceMakeTimeTicks: Int?
    public let ties: [MusicXMLTie]
    public let slurs: [MusicXMLSlur]
    public let tuplets: [MusicXMLTuplet]
    public let stem: MusicXMLStem
    public let beams: [MusicXMLBeam]
    public let staff: Int?
    public let voice: Int?
    public let attackTicks: Int?
    public let releaseTicks: Int?
    public let dynamicsOverrideVelocity: UInt8?
    public let articulations: Set<MusicXMLArticulation>
    public let arpeggiate: MusicXMLArpeggiate?
    public let performanceNotations: [MusicXMLPerformanceNotation]
    public let fingerings: [MusicXMLFingering]

    public var startsTie: Bool {
        ties.contains { $0.typeToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "start" }
    }

    public var stopsTie: Bool {
        ties.contains { $0.typeToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "stop" }
    }

    public init(
        sourceID: MusicXMLSourceNoteID? = nil,
        performedOccurrenceIndex: Int = 0,
        partID: String,
        measureNumber: Int,
        tick: Int,
        durationTicks: Int,
        hasExplicitDuration: Bool = true,
        writtenPitch: MusicXMLWrittenPitch? = nil,
        writtenRhythm: MusicXMLWrittenRhythm? = nil,
        noteheadToken: String? = nil,
        midiNote: Int?,
        isRest: Bool,
        isMeasureRest: Bool = false,
        isPrintObjectVisible: Bool = true,
        isChord: Bool,
        isGrace: Bool = false,
        graceSlash: Bool = false,
        graceStealTimePrevious: Double? = nil,
        graceStealTimeFollowing: Double? = nil,
        graceMakeTimeTicks: Int? = nil,
        ties: [MusicXMLTie] = [],
        slurs: [MusicXMLSlur] = [],
        tuplets: [MusicXMLTuplet] = [],
        stem: MusicXMLStem = .unspecified,
        beams: [MusicXMLBeam] = [],
        staff: Int?,
        voice: Int?,
        attackTicks: Int? = nil,
        releaseTicks: Int? = nil,
        dynamicsOverrideVelocity: UInt8? = nil,
        articulations: Set<MusicXMLArticulation> = [],
        arpeggiate: MusicXMLArpeggiate? = nil,
        performanceNotations: [MusicXMLPerformanceNotation] = [],
        fingerings: [MusicXMLFingering] = []
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = max(0, performedOccurrenceIndex)
        self.partID = partID
        self.measureNumber = measureNumber
        self.tick = tick
        self.durationTicks = durationTicks
        self.hasExplicitDuration = hasExplicitDuration
        self.writtenPitch = writtenPitch
        self.writtenRhythm = writtenRhythm
        self.noteheadToken = noteheadToken
        self.midiNote = midiNote
        self.isRest = isRest
        self.isMeasureRest = isMeasureRest
        self.isPrintObjectVisible = isPrintObjectVisible
        self.isChord = isChord
        self.isGrace = isGrace
        self.graceSlash = graceSlash
        self.graceStealTimePrevious = graceStealTimePrevious
        self.graceStealTimeFollowing = graceStealTimeFollowing
        self.graceMakeTimeTicks = graceMakeTimeTicks.map { max(0, $0) }
        self.ties = ties
        self.slurs = slurs
        self.tuplets = tuplets
        self.stem = stem
        self.beams = beams
        self.staff = staff
        self.voice = voice
        self.attackTicks = attackTicks
        self.releaseTicks = releaseTicks
        self.dynamicsOverrideVelocity = dynamicsOverrideVelocity
        self.articulations = articulations
        self.arpeggiate = arpeggiate
        self.performanceNotations = performanceNotations
        self.fingerings = fingerings
    }
}

public enum MusicXMLNoteType: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case oneThousandTwentyFourth = "1024th"
    case fiveHundredTwelfth = "512th"
    case twoHundredFiftySixth = "256th"
    case oneHundredTwentyEighth = "128th"
    case sixtyFourth = "64th"
    case thirtySecond = "32nd"
    case sixteenth = "16th"
    case eighth
    case quarter
    case half
    case whole
    case breve
    case long
    case maxima

    public init?(musicXMLToken: String) {
        self.init(rawValue: musicXMLToken.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum MusicXMLWrittenRhythmFailure: Error, Equatable, Sendable {
    case missingType
    case unsupportedType
    case missingDuration
    case invalidDuration
}

public struct MusicXMLWrittenRhythm: Equatable, Sendable {
    public let noteType: MusicXMLNoteType
    public let dotCount: Int
    public let timeModification: MusicXMLTimeModification?

    public init(
        noteType: MusicXMLNoteType,
        dotCount: Int = 0,
        timeModification: MusicXMLTimeModification? = nil
    ) {
        self.noteType = noteType
        self.dotCount = max(0, dotCount)
        self.timeModification = timeModification
    }
}

public struct MusicXMLTimeModification: Equatable, Sendable {
    public let actualNotes: Int?
    public let normalNotes: Int?
    public let normalTypeToken: String?
    public let normalDotCount: Int

    public init(
        actualNotes: Int?,
        normalNotes: Int?,
        normalTypeToken: String? = nil,
        normalDotCount: Int = 0
    ) {
        self.actualNotes = actualNotes
        self.normalNotes = normalNotes
        let trimmedType = normalTypeToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalTypeToken = trimmedType?.isEmpty == false ? trimmedType : nil
        self.normalDotCount = max(0, normalDotCount)
    }
}
