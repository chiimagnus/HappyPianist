import Foundation
import Observation

@MainActor
@Observable
final class PracticeFeedbackViewModel {
    private let sleeper: any SleeperProtocol
    private var dismissalTask: Task<Void, Never>?
    private(set) var cue: PracticeFeedbackEvent?
    private(set) var coachingPresentation: PracticeCoachingPresentation?

    init(sleeper: any SleeperProtocol = TaskSleeper()) {
        self.sleeper = sleeper
    }

    func present(
        _ event: PracticeFeedbackEvent?,
        coachingDecision: CoachingDecision? = nil
    ) {
        dismissalTask?.cancel()
        guard let event else {
            cue = nil
            coachingPresentation = nil
            return
        }
        cue = event
        coachingPresentation = coachingDecision.flatMap(Self.presentation)
        dismissalTask = Task { [weak self, sleeper] in
            try? await sleeper.sleep(for: .seconds(3))
            guard Task.isCancelled == false else { return }
            self?.cue = nil
            self?.coachingPresentation = nil
        }
    }

    func cancel() {
        dismissalTask?.cancel()
        dismissalTask = nil
        cue = nil
        coachingPresentation = nil
    }

    private static func presentation(for decision: CoachingDecision) -> PracticeCoachingPresentation? {
        var sourceLabels: [String] = []
        if let hand = decision.action.handFocus,
           let label = handSourceLabel(hand)
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
        return PracticeCoachingPresentation(
            actionLabel: actionLabel(decision.action),
            sourceLabel: sourceLabels.isEmpty ? nil : sourceLabels.joined(separator: "；"),
            fingeringText: decision.action.fingerings.fingeringDisplayText
        )
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
