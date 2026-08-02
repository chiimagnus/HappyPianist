import Foundation
import MusicXML

public struct PracticeHotspot: Equatable, Sendable {
    public let sourceMeasureID: PracticeSourceMeasureID

    public init(sourceMeasureID: PracticeSourceMeasureID) {
        self.sourceMeasureID = sourceMeasureID
    }
}

public enum PracticeNextAction: Equatable, Sendable {
    case retryMeasure(PracticeSourceMeasureID)
    case lowerTempo(Double)
    case keepTempo
    case expandPassage
    case continuePassage
}

public struct CoachingDecision: Equatable, Sendable {
    public let issue: MusicalIssue
    public let action: CoachingAction

    public init(issue: MusicalIssue, action: CoachingAction) {
        self.issue = issue
        self.action = action
    }
}

public struct PracticeCoachingPresentation: Equatable, Sendable {
    public let actionLabel: String
    public let sourceLabel: String?
    public let fingeringText: String?

    public init(decision: CoachingDecision) {
        var sourceLabels: [String] = []
        if let hand = decision.action.handFocus,
           let label = Self.handSourceLabel(hand)
        {
            sourceLabels.append("手部依据：\(label)")
        }
        let fingeringSources = Set(decision.action.fingerings.map(\.provenance))
        let orderedFingeringLabels: [(MusicXMLFingeringProvenance, String)] = [
            (.score, "原谱"),
            (.teacher, "教师"),
            (.user, "你的确认"),
        ]
        let fingeringLabels = orderedFingeringLabels.compactMap { source, label in
            fingeringSources.contains(source) ? label : nil
        }
        if fingeringLabels.isEmpty == false {
            sourceLabels.append("指法依据：\(fingeringLabels.joined(separator: "、"))")
        }
        if let voice = decision.action.voiceFocus {
            sourceLabels.append(
                "目标声部：谱面 \(voice.partID) / 第 \(voice.staff) 谱表 / 声部 \(voice.voice)"
            )
        }
        if let referenceUse = decision.action.referenceUse {
            let referenceLabel = switch referenceUse {
            case .score: "参考：当前谱面"
            case .manualReplay: "参考：示范回放"
            }
            sourceLabels.append(referenceLabel)
        }
        actionLabel = Self.actionLabel(decision.action)
        sourceLabel = sourceLabels.isEmpty ? nil : sourceLabels.joined(separator: "；")
        fingeringText = decision.action.fingerings.fingeringDisplayText
    }

    private static func actionLabel(_ action: CoachingAction) -> String {
        let instruction = switch action.kind {
        case .pitchAccuracy: "确认音高后重练"
        case .onsetAlignment: "跟随节拍对齐落键"
        case .chordSynchronization: "让和弦同时落下"
        case .durationControl: "保持完整音值"
        case .articulationControl: "按谱面衔接音符"
        case .voiceBalance: "突出目标声部"
        case .dynamicShaping: "练习力度走向"
        case .pedalCoordination: "对齐踏板更换"
        case .tempoStability: "保持速度连贯"
        case .phraseContinuity: "连贯完成乐句"
        case .evidenceCheck: "再演奏一次以补充证据"
        }
        guard action.kind != .evidenceCheck else { return instruction }
        let tempo = action.tempoRatio.map {
            "，速度不高于 \($0.formatted(.percent.precision(.fractionLength(0))))"
        } ?? ""
        return "\(instruction)\(tempo)，重复 \(action.repeatCount) 次"
    }

    private static func handSourceLabel(_ assignment: ScoreHandAssignment) -> String? {
        switch assignment.provenance {
        case .score:
            "原谱"
        case .teacher:
            "教师"
        case .user:
            "你的确认"
        case .heuristic:
            assignment.confidence.map {
                "推测（\($0.formatted(.percent.precision(.fractionLength(0))))）"
            } ?? "推测"
        case .unresolved:
            nil
        }
    }
}

public struct PracticeFeedbackContext: Equatable, Sendable {
    public let passageFacts: [MeasurePracticeFacts]
    public let passageSourceMeasureIDs: Set<PracticeSourceMeasureID>
    public let configuration: PracticeRoundConfiguration
    public let isFullPassage: Bool
    public let coachingDecision: CoachingDecision?

    public init(
        passageFacts: [MeasurePracticeFacts],
        passageSourceMeasureIDs: Set<PracticeSourceMeasureID>,
        configuration: PracticeRoundConfiguration,
        isFullPassage: Bool,
        coachingDecision: CoachingDecision? = nil
    ) {
        self.passageFacts = passageFacts
        self.passageSourceMeasureIDs = passageSourceMeasureIDs
        self.configuration = configuration
        self.isFullPassage = isFullPassage
        self.coachingDecision = coachingDecision
    }
}

public enum PracticePassageCoverage {
    public static func hasStablePitchSteps(
        facts: [MeasurePracticeFacts],
        sourceMeasureIDs: Set<PracticeSourceMeasureID>
    ) -> Bool {
        guard sourceMeasureIDs.isEmpty == false else { return false }
        let stableIDs = Set(facts.lazy.filter { $0.state == .pitchStepStable }.map(\.sourceMeasureID))
        return sourceMeasureIDs.isSubset(of: stableIDs)
    }
}
