import Foundation

struct MusicXMLScore: Equatable {
    var scoreVersion: String?
    var partMetadata: [MusicXMLPartMetadata] = []
    var logicalInstruments: [MusicXMLLogicalInstrument] = []
    var notes: [MusicXMLNoteEvent]
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
}

struct MusicXMLEventScope: Equatable, Sendable {
    let partID: String
    let staff: Int?
    let voice: Int?
}

enum MusicXMLDynamicEventSource: Equatable {
    case directionDynamics
    case soundDynamicsAttribute
}

struct MusicXMLDynamicEvent: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let tick: Int
    let velocity: UInt8
    let scope: MusicXMLEventScope
    let source: MusicXMLDynamicEventSource
}

enum MusicXMLWedgeKind: Equatable, Sendable {
    case crescendoStart
    case diminuendoStart
    case stop
}

struct MusicXMLWedgeEvent: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let tick: Int
    let kind: MusicXMLWedgeKind
    let numberToken: String?
    let scope: MusicXMLEventScope
}

struct MusicXMLWedgePairKey: Equatable, Hashable, Sendable {
    let partID: String
    let staff: Int?
    let voice: Int?
    let numberToken: String
}

extension MusicXMLWedgeEvent {
    var normalizedNumberToken: String {
        guard let token = numberToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              token.isEmpty == false
        else {
            return "1"
        }
        return token
    }

    var pairKey: MusicXMLWedgePairKey {
        MusicXMLWedgePairKey(
            partID: scope.partID,
            staff: scope.staff,
            voice: scope.voice,
            numberToken: normalizedNumberToken
        )
    }
}

struct MusicXMLWedgeApproximation: Equatable, Sendable {
    let sourceID: MusicXMLDirectionSourceID?
    let reason: String
}

enum MusicXMLFermataEventSource: Equatable {
    case noteNotations
    case directionType
}

struct MusicXMLFermataEvent: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let tick: Int
    let scope: MusicXMLEventScope
    let source: MusicXMLFermataEventSource
}

enum MusicXMLArpeggiateDirection: String, Codable, Equatable, Hashable, Sendable {
    case up
    case down
}

struct MusicXMLArpeggiate: Equatable, Hashable, Sendable {
    let numberToken: String?
    let directionToken: String?

    var normalizedNumberToken: String {
        guard let trimmed = numberToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return "1"
        }
        return trimmed
    }

    var direction: MusicXMLArpeggiateDirection? {
        guard let token = directionToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        return MusicXMLArpeggiateDirection(rawValue: token)
    }
}

struct MusicXMLTimeSignatureEvent: Equatable, Identifiable {
    var id: String { "\(tick)-\(meter.displayText)-\(scope.partID)" }

    let tick: Int
    let meter: MusicXMLMeter
    let scope: MusicXMLEventScope

    var beats: Int { meter.totalBeats }
    var beatType: Int { meter.primaryBeatType }

    init(tick: Int, meter: MusicXMLMeter, scope: MusicXMLEventScope) {
        self.tick = tick
        self.meter = meter
        self.scope = scope
    }

    init(tick: Int, beats: Int, beatType: Int, scope: MusicXMLEventScope) {
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

struct MusicXMLKeySignatureEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(fifths)-\(modeToken ?? "")-\(scope.partID)"
    }

    let tick: Int
    let fifths: Int
    let modeToken: String?
    let scope: MusicXMLEventScope
}

struct MusicXMLClefEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(signToken ?? "")-\(line ?? -1)-\(octaveChange ?? 0)-\(numberToken ?? "")-\(scope.partID)"
    }

    let tick: Int
    let signToken: String?
    let line: Int?
    let octaveChange: Int?
    let numberToken: String?
    let scope: MusicXMLEventScope
}

struct MusicXMLWordsEvent: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let tick: Int
    let text: String
    let scope: MusicXMLEventScope
}

enum MusicXMLArticulation: String, CaseIterable, Equatable, Hashable {
    case staccato
    case accent
    case tenuto
    case marcato
    case staccatissimo
    case detachedLegato = "detached-legato"
}

struct MusicXMLTempoEvent: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let tick: Int
    let quarterBPM: Double
    let scope: MusicXMLEventScope
}

struct MusicXMLSoundDirective: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let partID: String
    let measureNumber: Int
    let tick: Int
    let segno: String?
    let coda: String?
    let tocoda: String?
    let dalsegno: String?
    let dacapo: String?
    let timeOnlyPasses: [Int]?
}

enum MusicXMLPedalEventKind: String, Equatable {
    case start
    case stop
    case change
    case `continue`
}

struct MusicXMLPedalEvent: Equatable {
    var sourceID: MusicXMLDirectionSourceID? = nil
    var performedOccurrenceIndex: Int = 0
    var performedID: MusicXMLPerformedDirectionID? {
        sourceID.map { MusicXMLPerformedDirectionID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }
    let partID: String
    let measureNumber: Int
    let tick: Int
    let kind: MusicXMLPedalEventKind
    var controller: MusicXMLPedalController = .damper
    let value: MusicXMLControllerValue?
    let timeOnlyPasses: [Int]?
}

struct MusicXMLMeasureSpan: Equatable, Identifiable {
    var id: String {
        "\(partID)-\(sourceMeasureIndex)-\(occurrenceIndex)-\(startTick)-\(endTick)"
    }

    let partID: String
    let measureNumber: Int
    let sourceMeasureIndex: Int
    let sourceMeasureNumberToken: String?
    let occurrenceIndex: Int
    let startTick: Int
    let endTick: Int

    var sourceMeasureID: PracticeSourceMeasureID {
        PracticeSourceMeasureID(
            partID: partID,
            sourceMeasureIndex: sourceMeasureIndex,
            sourceNumberToken: sourceMeasureNumberToken
        )
    }

    var occurrenceID: PracticeMeasureOccurrenceID {
        PracticeMeasureOccurrenceID(
            sourceMeasureID: sourceMeasureID,
            occurrenceIndex: occurrenceIndex
        )
    }
}

enum MusicXMLRepeatDirection: String, Equatable {
    case forward
    case backward
}

struct MusicXMLRepeatDirective: Equatable {
    let partID: String
    let measureNumber: Int
    let direction: MusicXMLRepeatDirection
    let times: Int?

    init(
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

enum MusicXMLEndingType: String, Equatable {
    case start
    case stop
    case discontinue
}

struct MusicXMLEndingDirective: Equatable {
    let partID: String
    let measureNumber: Int
    let number: String
    let type: MusicXMLEndingType
}

struct MusicXMLNoteEvent: Equatable, Identifiable {
    var id: MusicXMLPerformedNoteID? { performedID }
    var performedID: MusicXMLPerformedNoteID? {
        sourceID.map { MusicXMLPerformedNoteID(sourceID: $0, occurrenceIndex: performedOccurrenceIndex) }
    }

    let sourceID: MusicXMLSourceNoteID?
    let performedOccurrenceIndex: Int
    let partID: String
    let measureNumber: Int
    let tick: Int
    let durationTicks: Int
    let writtenPitch: MusicXMLWrittenPitch?
    let writtenRhythm: MusicXMLWrittenRhythm?
    let midiNote: Int?
    let isRest: Bool
    let isChord: Bool
    let isGrace: Bool
    let graceSlash: Bool
    let graceStealTimePrevious: Double?
    let graceStealTimeFollowing: Double?
    let graceMakeTimeTicks: Int?
    let tieStart: Bool
    let tieStop: Bool
    let staff: Int?
    let voice: Int?
    let attackTicks: Int?
    let releaseTicks: Int?
    let dynamicsOverrideVelocity: UInt8?
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let performanceNotations: [MusicXMLPerformanceNotation]
    let fingeringText: String?

    init(
        sourceID: MusicXMLSourceNoteID? = nil,
        performedOccurrenceIndex: Int = 0,
        partID: String,
        measureNumber: Int,
        tick: Int,
        durationTicks: Int,
        writtenPitch: MusicXMLWrittenPitch? = nil,
        writtenRhythm: MusicXMLWrittenRhythm? = nil,
        midiNote: Int?,
        isRest: Bool,
        isChord: Bool,
        isGrace: Bool = false,
        graceSlash: Bool = false,
        graceStealTimePrevious: Double? = nil,
        graceStealTimeFollowing: Double? = nil,
        graceMakeTimeTicks: Int? = nil,
        tieStart: Bool,
        tieStop: Bool,
        staff: Int?,
        voice: Int?,
        attackTicks: Int? = nil,
        releaseTicks: Int? = nil,
        dynamicsOverrideVelocity: UInt8? = nil,
        articulations: Set<MusicXMLArticulation> = [],
        arpeggiate: MusicXMLArpeggiate? = nil,
        performanceNotations: [MusicXMLPerformanceNotation] = [],
        fingeringText: String? = nil
    ) {
        self.sourceID = sourceID
        self.performedOccurrenceIndex = max(0, performedOccurrenceIndex)
        self.partID = partID
        self.measureNumber = measureNumber
        self.tick = tick
        self.durationTicks = durationTicks
        self.writtenPitch = writtenPitch
        self.writtenRhythm = writtenRhythm
        self.midiNote = midiNote
        self.isRest = isRest
        self.isChord = isChord
        self.isGrace = isGrace
        self.graceSlash = graceSlash
        self.graceStealTimePrevious = graceStealTimePrevious
        self.graceStealTimeFollowing = graceStealTimeFollowing
        self.graceMakeTimeTicks = graceMakeTimeTicks.map { max(0, $0) }
        self.tieStart = tieStart
        self.tieStop = tieStop
        self.staff = staff
        self.voice = voice
        self.attackTicks = attackTicks
        self.releaseTicks = releaseTicks
        self.dynamicsOverrideVelocity = dynamicsOverrideVelocity
        self.articulations = articulations
        self.arpeggiate = arpeggiate
        self.performanceNotations = performanceNotations
        self.fingeringText = fingeringText
    }
}

struct MusicXMLWrittenRhythm: Equatable, Sendable {
    let typeToken: String?
    let dotCount: Int
    let timeModification: MusicXMLTimeModification?

    init(
        typeToken: String?,
        dotCount: Int = 0,
        timeModification: MusicXMLTimeModification? = nil
    ) {
        let trimmedType = typeToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.typeToken = trimmedType?.isEmpty == false ? trimmedType : nil
        self.dotCount = max(0, dotCount)
        self.timeModification = timeModification
    }
}

struct MusicXMLTimeModification: Equatable, Sendable {
    let actualNotes: Int?
    let normalNotes: Int?
    let normalTypeToken: String?
    let normalDotCount: Int

    init(
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
