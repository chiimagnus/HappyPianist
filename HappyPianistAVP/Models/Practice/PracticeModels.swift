import Foundation

enum PianoGuideHighlightPhase: String, Equatable, Hashable {
    case active
    case triggered
}

enum ScoreHand: String, CaseIterable, Codable, Sendable {
    case right
    case left
    case unknown

    static func fromStaff(_ staff: Int?) -> ScoreHand {
        guard let staff else { return .right }
        if staff <= 1 { return .right }
        return .left
    }
}

enum PracticeHandMode: String, CaseIterable, Identifiable, Codable {
    case both
    case right
    case left

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .both:
            "双手"
        case .right:
            "右手"
        case .left:
            "左手"
        }
    }

    var focusedHand: ScoreHand? {
        switch self {
        case .both:
            nil
        case .right:
            .right
        case .left:
            .left
        }
    }

    func allows(hand: ScoreHand) -> Bool {
        guard let focusedHand else { return true }
        return hand == focusedHand
    }

    static func storageValue(from rawValue: String?) -> PracticeHandMode {
        guard let rawValue else { return .both }
        return PracticeHandMode(rawValue: rawValue) ?? .both
    }
}

struct DetectedNoteEvent: Equatable {
    let midiNote: Int
    let confidence: Double
    let onsetScore: Double
    let isOnset: Bool
    let timestamp: Date
    let generation: Int
}

struct PracticeStepNote: Equatable, Hashable, Identifiable {
    var id: String {
        "\(midiNote)-\(hand.rawValue)-\(staff ?? -1)-\(voice ?? -1)-\(onTickOffset)"
    }

    let midiNote: Int
    let handAssignment: ScoreHandAssignment
    var hand: ScoreHand { handAssignment.hand }
    let staff: Int?
    let voice: Int?
    let velocity: UInt8
    let onTickOffset: Int
    let fingeringText: String?

    init(
        midiNote: Int,
        staff: Int?,
        voice: Int? = nil,
        velocity: UInt8 = 96,
        onTickOffset: Int = 0,
        fingeringText: String? = nil,
        handAssignment: ScoreHandAssignment? = nil,
        hand: ScoreHand? = nil
    ) {
        self.midiNote = midiNote
        self.staff = staff
        self.voice = voice
        self.velocity = velocity
        self.onTickOffset = onTickOffset
        self.fingeringText = fingeringText
        self.handAssignment = handAssignment
            ?? hand.map { ScoreHandAssignment(hand: $0, provenance: .score) }
            ?? .unknown
    }
}

struct PracticeStep: Equatable, Identifiable {
    var id: Int {
        tick
    }

    let tick: Int
    let notes: [PracticeStepNote]
}

struct PracticeStepBuildResult: Equatable {
    let steps: [PracticeStep]
    let unsupportedNoteCount: Int
}

struct PreparedPractice {
    let identity: PracticeSongIdentity
    let steps: [PracticeStep]
    let file: ImportedMusicXMLFile
    let tempoMap: MusicXMLTempoMap
    let pedalTimeline: MusicXMLPedalTimeline?
    let fermataTimeline: MusicXMLFermataTimeline?
    let attributeTimeline: MusicXMLAttributeTimeline?
    let highlightGuides: [PianoHighlightGuide]
    let measureSpans: [MusicXMLMeasureSpan]
    let unsupportedNoteCount: Int
}

enum ManualAdvanceMode: String, CaseIterable, Identifiable, Codable, Equatable {
    case step
    case measure

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .step:
            "逐步"
        case .measure:
            "按小节"
        }
    }

    var nextButtonTitle: String {
        switch self {
        case .step:
            "下一步"
        case .measure:
            "下一节"
        }
    }

    var replayButtonTitle: String {
        switch self {
        case .step:
            "播放琴声"
        case .measure:
            "重播本节"
        }
    }

    static func storageValue(from rawValue: String?) -> ManualAdvanceMode {
        guard let rawValue else { return .step }
        return ManualAdvanceMode(rawValue: rawValue) ?? .step
    }
}

enum StepAttemptMatchResult: Equatable {
    case matched
    case wrongNote
    case missingNotes
    case incompleteChord
    case insufficientEvidence

    var isMatched: Bool {
        self == .matched
    }
}
