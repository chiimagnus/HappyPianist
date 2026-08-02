import Foundation
import MusicXML

public enum PracticeHandMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case both
    case right
    case left

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .both:
            "双手"
        case .right:
            "右手"
        case .left:
            "左手"
        }
    }

    public var focusedHand: ScoreHand? {
        switch self {
        case .both:
            nil
        case .right:
            .right
        case .left:
            .left
        }
    }

    public func allows(hand: ScoreHand) -> Bool {
        guard let focusedHand else { return true }
        return hand == focusedHand
    }

    public static func storageValue(from rawValue: String?) -> PracticeHandMode {
        guard let rawValue else { return .both }
        return PracticeHandMode(rawValue: rawValue) ?? .both
    }
}

public struct PracticeStepNote: Equatable, Hashable, Identifiable, Sendable {
    public var id: String {
        "\(midiNote)-\(hand.rawValue)-\(staff ?? -1)-\(voice ?? -1)-\(onTickOffset)"
    }

    public let midiNote: Int
    public let handAssignment: ScoreHandAssignment
    public var hand: ScoreHand {
        handAssignment.hand
    }

    public let staff: Int?
    public let voice: Int?
    public let velocity: UInt8
    public let onTickOffset: Int
    public let fingerings: [MusicXMLFingering]
    public let sourceNoteIDs: [MusicXMLSourceNoteID]

    public init(
        midiNote: Int,
        staff: Int?,
        voice: Int? = nil,
        velocity: UInt8 = 96,
        onTickOffset: Int = 0,
        fingerings: [MusicXMLFingering] = [],
        sourceNoteIDs: [MusicXMLSourceNoteID] = [],
        handAssignment: ScoreHandAssignment
    ) {
        self.midiNote = midiNote
        self.staff = staff
        self.voice = voice
        self.velocity = velocity
        self.onTickOffset = onTickOffset
        self.fingerings = fingerings
        self.sourceNoteIDs = sourceNoteIDs
        self.handAssignment = handAssignment
    }
}

public struct PracticeStep: Equatable, Identifiable, Sendable {
    public var id: Int {
        tick
    }

    public let tick: Int
    public let notes: [PracticeStepNote]

    public init(tick: Int, notes: [PracticeStepNote]) {
        self.tick = tick
        self.notes = notes
    }
}

public struct PracticeStepBuildResult: Equatable, Sendable {
    public let steps: [PracticeStep]
    public let unsupportedNoteCount: Int

    public init(steps: [PracticeStep], unsupportedNoteCount: Int) {
        self.steps = steps
        self.unsupportedNoteCount = unsupportedNoteCount
    }
}

public struct PreparedPracticeScoreContext: Equatable, Sendable {
    public let sourceScore: MusicXMLScore
    public let preparedScore: MusicXMLScore
    public let logicalInstrument: MusicXMLLogicalInstrument
    public let structuralPartID: String
    public let orderSelection: MusicXMLOrderSelection
    public let handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment]

    public init(
        sourceScore: MusicXMLScore,
        preparedScore: MusicXMLScore,
        logicalInstrument: MusicXMLLogicalInstrument,
        structuralPartID: String,
        orderSelection: MusicXMLOrderSelection,
        handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment]
    ) {
        self.sourceScore = sourceScore
        self.preparedScore = preparedScore
        self.logicalInstrument = logicalInstrument
        self.structuralPartID = structuralPartID
        self.orderSelection = orderSelection
        self.handAssignments = handAssignments
    }
}

public struct PreparedPractice: Sendable {
    public let identity: PracticeSongIdentity
    public let performancePlan: ScorePerformancePlan
    public let notationProjection: ScoreNotationProjection
    public let steps: [PracticeStep]
    public let file: ImportedMusicXMLFile
    public let attributeTimeline: MusicXMLAttributeTimeline?
    public let highlightGuides: [PianoHighlightGuide]
    public let measureSpans: [MusicXMLMeasureSpan]
    public let unsupportedNoteCount: Int
    public let scoreContext: PreparedPracticeScoreContext

    public init(
        identity: PracticeSongIdentity,
        performancePlan: ScorePerformancePlan,
        notationProjection: ScoreNotationProjection,
        steps: [PracticeStep],
        file: ImportedMusicXMLFile,
        attributeTimeline: MusicXMLAttributeTimeline?,
        highlightGuides: [PianoHighlightGuide],
        measureSpans: [MusicXMLMeasureSpan],
        unsupportedNoteCount: Int,
        scoreContext: PreparedPracticeScoreContext
    ) {
        self.identity = identity
        self.performancePlan = performancePlan
        self.notationProjection = notationProjection
        self.steps = steps
        self.file = file
        self.attributeTimeline = attributeTimeline
        self.highlightGuides = highlightGuides
        self.measureSpans = measureSpans
        self.unsupportedNoteCount = unsupportedNoteCount
        self.scoreContext = scoreContext
    }
}
