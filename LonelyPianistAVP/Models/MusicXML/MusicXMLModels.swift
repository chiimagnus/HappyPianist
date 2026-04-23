import Foundation

struct MusicXMLScore: Equatable {
    var scoreVersion: String?
    var notes: [MusicXMLNoteEvent]
    var tempoEvents: [MusicXMLTempoEvent] = []
    var soundDirectives: [MusicXMLSoundDirective] = []
    var pedalEvents: [MusicXMLPedalEvent] = []
    var dynamicEvents: [MusicXMLDynamicEvent] = []
    var wedgeEvents: [MusicXMLWedgeEvent] = []
    var fermataEvents: [MusicXMLFermataEvent] = []
    var slurEvents: [MusicXMLSlurEvent] = []
    var timeSignatureEvents: [MusicXMLTimeSignatureEvent] = []
    var keySignatureEvents: [MusicXMLKeySignatureEvent] = []
    var clefEvents: [MusicXMLClefEvent] = []
    var wordsEvents: [MusicXMLWordsEvent] = []
    var measures: [MusicXMLMeasureSpan] = []
    var repeatDirectives: [MusicXMLRepeatDirective] = []
    var endingDirectives: [MusicXMLEndingDirective] = []
}

struct MusicXMLEventScope: Equatable {
    let partID: String
    let staff: Int?
    let voice: Int?
}

enum MusicXMLDynamicEventSource: Equatable {
    case directionDynamics
    case soundDynamicsAttribute
}

struct MusicXMLDynamicEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(velocity)-\(scope.partID)-\(scope.staff ?? -1)-\(scope.voice ?? -1)-\(source)"
    }

    let tick: Int
    let velocity: UInt8
    let scope: MusicXMLEventScope
    let source: MusicXMLDynamicEventSource
}

enum MusicXMLWedgeKind: Equatable {
    case crescendoStart
    case diminuendoStart
    case stop
}

struct MusicXMLWedgeEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(kind)-\(numberToken ?? "")-\(scope.partID)-\(scope.staff ?? -1)-\(scope.voice ?? -1)"
    }

    let tick: Int
    let kind: MusicXMLWedgeKind
    let numberToken: String?
    let scope: MusicXMLEventScope
}

enum MusicXMLFermataEventSource: Equatable {
    case noteNotations
    case directionType
}

struct MusicXMLFermataEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(scope.partID)-\(scope.staff ?? -1)-\(scope.voice ?? -1)-\(source)"
    }

    let tick: Int
    let scope: MusicXMLEventScope
    let source: MusicXMLFermataEventSource
}

struct MusicXMLArpeggiate: Equatable {
    let numberToken: String?
    let directionToken: String?
}

enum MusicXMLSlurEventKind: Equatable {
    case start
    case stop
}

struct MusicXMLSlurEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(kind)-\(numberToken ?? "")-\(scope.partID)-\(scope.staff ?? -1)-\(scope.voice ?? -1)"
    }

    let tick: Int
    let kind: MusicXMLSlurEventKind
    let numberToken: String?
    let scope: MusicXMLEventScope
}

struct MusicXMLTimeSignatureEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(beats)-\(beatType)-\(scope.partID)"
    }

    let tick: Int
    let beats: Int
    let beatType: Int
    let scope: MusicXMLEventScope
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

struct MusicXMLWordsEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(scope.partID)-\(scope.staff ?? -1)-\(scope.voice ?? -1)-\(text)"
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

struct MusicXMLTempoEvent: Equatable, Identifiable {
    var id: String {
        "\(tick)-\(quarterBPM)"
    }

    let tick: Int
    let quarterBPM: Double
}

struct MusicXMLSoundDirective: Equatable, Identifiable {
    var id: String {
        "\(partID)-\(measureNumber)-\(tick)-\(segno ?? "")-\(coda ?? "")-\(tocoda ?? "")-\(dalsegno ?? "")-\(dacapo ?? "")-\(timeOnlyPasses?.map(String.init).joined(separator: ",") ?? "")"
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

struct MusicXMLPedalEvent: Equatable, Identifiable {
    var id: String {
        "\(partID)-\(measureNumber)-\(tick)-\(kind.rawValue)-\(isDown.map { $0 ? "down" : "up" } ?? "keep")-\(timeOnlyPasses?.map(String.init).joined(separator: ",") ?? "")"
    }

    let partID: String
    let measureNumber: Int
    let tick: Int
    let kind: MusicXMLPedalEventKind
    let isDown: Bool?
    let timeOnlyPasses: [Int]?
}

struct MusicXMLMeasureSpan: Equatable, Identifiable {
    var id: String {
        "\(partID)-\(measureIndex)-\(startTick)-\(endTick)"
    }

    let partID: String
    let measureNumber: Int
    let measureIndex: Int
    let measureNumberToken: String?
    let startTick: Int
    let endTick: Int

    init(partID: String, measureNumber: Int, startTick: Int, endTick: Int) {
        self.partID = partID
        self.measureNumber = measureNumber
        measureIndex = measureNumber
        measureNumberToken = nil
        self.startTick = startTick
        self.endTick = endTick
    }

    init(
        partID: String,
        measureNumber: Int,
        measureIndex: Int,
        measureNumberToken: String?,
        startTick: Int,
        endTick: Int
    ) {
        self.partID = partID
        self.measureNumber = measureNumber
        self.measureIndex = measureIndex
        self.measureNumberToken = measureNumberToken
        self.startTick = startTick
        self.endTick = endTick
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
    var id: String {
        "\(partID)-\(measureNumber)-\(tick)-\(midiNote ?? -1)-\(durationTicks)-\(isRest)-\(isChord)-\(isGrace)-\(graceSlash)-\(graceStealTimePrevious ?? 0)-\(graceStealTimeFollowing ?? 0)-\(tieStart)-\(tieStop)-\(attackTicks ?? 0)-\(releaseTicks ?? 0)-\(dynamicsOverrideVelocity ?? 0)-\(articulations.map(\.rawValue).sorted().joined(separator: ","))-\(arpeggiate?.numberToken ?? "")-\(arpeggiate?.directionToken ?? "")-\(fingeringText ?? "")"
    }

    let partID: String
    let measureNumber: Int
    let tick: Int
    let durationTicks: Int
    let midiNote: Int?
    let isRest: Bool
    let isChord: Bool
    let isGrace: Bool
    let graceSlash: Bool
    let graceStealTimePrevious: Double?
    let graceStealTimeFollowing: Double?
    let tieStart: Bool
    let tieStop: Bool
    let staff: Int?
    let voice: Int?
    let attackTicks: Int?
    let releaseTicks: Int?
    let dynamicsOverrideVelocity: UInt8?
    let articulations: Set<MusicXMLArticulation>
    let arpeggiate: MusicXMLArpeggiate?
    let fingeringText: String?

    init(
        partID: String,
        measureNumber: Int,
        tick: Int,
        durationTicks: Int,
        midiNote: Int?,
        isRest: Bool,
        isChord: Bool,
        isGrace: Bool = false,
        graceSlash: Bool = false,
        graceStealTimePrevious: Double? = nil,
        graceStealTimeFollowing: Double? = nil,
        tieStart: Bool,
        tieStop: Bool,
        staff: Int?,
        voice: Int?,
        attackTicks: Int? = nil,
        releaseTicks: Int? = nil,
        dynamicsOverrideVelocity: UInt8? = nil,
        articulations: Set<MusicXMLArticulation> = [],
        arpeggiate: MusicXMLArpeggiate? = nil,
        fingeringText: String? = nil
    ) {
        self.partID = partID
        self.measureNumber = measureNumber
        self.tick = tick
        self.durationTicks = durationTicks
        self.midiNote = midiNote
        self.isRest = isRest
        self.isChord = isChord
        self.isGrace = isGrace
        self.graceSlash = graceSlash
        self.graceStealTimePrevious = graceStealTimePrevious
        self.graceStealTimeFollowing = graceStealTimeFollowing
        self.tieStart = tieStart
        self.tieStop = tieStop
        self.staff = staff
        self.voice = voice
        self.attackTicks = attackTicks
        self.releaseTicks = releaseTicks
        self.dynamicsOverrideVelocity = dynamicsOverrideVelocity
        self.articulations = articulations
        self.arpeggiate = arpeggiate
        self.fingeringText = fingeringText
    }
}

struct MusicXMLNoteSpan: Equatable, Identifiable {
    var id: String {
        "\(midiNote)-\(staff)-\(voice)-\(onTick)-\(offTick)"
    }

    let midiNote: Int
    let staff: Int
    let voice: Int
    let onTick: Int
    let offTick: Int
}
