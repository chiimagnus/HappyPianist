import Foundation

struct MusicXMLScore: Equatable {
    var scoreVersion: String? = nil
    var notes: [MusicXMLNoteEvent]
    var tempoEvents: [MusicXMLTempoEvent] = []
    var soundDirectives: [MusicXMLSoundDirective] = []
    var pedalEvents: [MusicXMLPedalEvent] = []
    var measures: [MusicXMLMeasureSpan] = []
    var repeatDirectives: [MusicXMLRepeatDirective] = []
    var endingDirectives: [MusicXMLEndingDirective] = []
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

    init(partID: String, measureNumber: Int, measureIndex: Int, measureNumberToken: String?, startTick: Int, endTick: Int) {
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
        "\(partID)-\(measureNumber)-\(tick)-\(midiNote ?? -1)-\(durationTicks)-\(isRest)-\(isChord)-\(tieStart)-\(tieStop)"
    }

    let partID: String
    let measureNumber: Int
    let tick: Int
    let durationTicks: Int
    let midiNote: Int?
    let isRest: Bool
    let isChord: Bool
    let tieStart: Bool
    let tieStop: Bool
    let staff: Int?
    let voice: Int?
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
