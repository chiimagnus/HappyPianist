import Practice
import SwiftUI

public struct GrandStaffNotationSpreadView: View {
    let plan: GrandStaffNotationPagePlan
    let targetIndex: Int
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    let annotations: [GrandStaffNotationMeasureAnnotation]
    let onTurnBackward: (() -> Void)?
    let onTurnForward: (() -> Void)?
    @State private var enlarged = false
    @State private var turn = GrandStaffNotationPageTurnState()
    @State private var progress = 0.0

    public init(plan: GrandStaffNotationPagePlan, targetIndex: Int, overlay: ScoreNotationProjection.Overlay = .empty, practiceHandMode: PracticeHandMode = .both, annotations: [GrandStaffNotationMeasureAnnotation] = [], onTurnBackward: (() -> Void)? = nil, onTurnForward: (() -> Void)? = nil) {
        self.plan = plan
        self.targetIndex = targetIndex
        self.overlay = overlay
        self.practiceHandMode = practiceHandMode
        self.annotations = annotations
        self.onTurnBackward = onTurnBackward
        self.onTurnForward = onTurnForward
    }

    public var body: some View {
        GeometryReader { geometry in
            let magnified = enlarged
            let staffSpace = min(geometry.size.width / plan.geometry.spreadWidth, geometry.size.height / plan.geometry.height)
            if (0..<plan.spreadCount).contains(targetIndex) {
                if magnified {
                    ScrollView(.vertical) {
                        VStack(spacing: plan.geometry.gutter * geometry.size.width / plan.geometry.width) {
                            ForEach(targetIndex * 2..<min(targetIndex * 2 + 2, plan.pages.count), id: \.self) { index in
                                GrandStaffNotationPageView(plan: plan, index: index, staffSpace: geometry.size.width / plan.geometry.width, overlay: overlay, practiceHandMode: practiceHandMode, annotations: annotations)
                            }
                        }
                    }
                } else {
                    let transition = if let active = turn.transition, active.identity == plan.turnIdentity, active.target == targetIndex { active } else {
                        GrandStaffNotationPageTurnState.Transition(identity: plan.turnIdentity, generation: turn.generation, source: targetIndex, target: targetIndex)
                    }
                    GrandStaffNotationPageTurnView(plan: plan, transition: transition, staffSpace: staffSpace, overlay: overlay, practiceHandMode: practiceHandMode, annotations: annotations, progress: progress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("曲谱位置无效", systemImage: "music.note")
            }
        }
        .onChange(of: Request(identity: plan.turnIdentity, target: targetIndex, animated: !enlarged), initial: true) { _, request in
            var next = turn
            next.request(identity: request.identity, target: request.target, animated: request.animated)
            guard next != turn else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                turn = next
                progress = 0
            }
            if let transition = next.transition {
                withAnimation(.easeInOut(duration: 0.55), completionCriteria: .removed) {
                    progress = 1
                } completion: {
                    guard turn.transition == transition else { return }
                    withTransaction(transaction) {
                        turn.complete(transition)
                        progress = 0
                    }
                }
            }
        }
        .onDisappear { turn.clear() }
        .overlay(alignment: .leading) {
            if let onTurnBackward {
                Button("上一双页", systemImage: "chevron.left", action: onTurnBackward)
                    .labelStyle(.iconOnly)
                    .controlSize(.large)
                    .padding(.leading, 4)
            }
        }
        .overlay(alignment: .trailing) {
            if let onTurnForward {
                Button("下一双页", systemImage: "chevron.right", action: onTurnForward)
                    .labelStyle(.iconOnly)
                    .controlSize(.large)
                    .padding(.trailing, 4)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(enlarged ? "恢复双页" : "放大阅读", systemImage: enlarged ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { enlarged.toggle() }
                .labelStyle(.iconOnly)
                .padding(.trailing)
        }
    }

    private struct Request: Equatable {
        let identity: GrandStaffNotationPageTurnIdentity
        let target: Int
        let animated: Bool
    }

}

public struct GrandStaffNotationBookView: View {
    let input: GrandStaffNotationScoreInput
    let navigationTick: Int?
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    let navigationRange: Range<Int>?
    let onNavigate: ((Int) -> Void)?
    @State private var owner = GrandStaffNotationPageViewModel()

    public init(input: GrandStaffNotationScoreInput, navigationTick: Int?, overlay: ScoreNotationProjection.Overlay = .empty, practiceHandMode: PracticeHandMode = .both, navigationRange: Range<Int>? = nil, onNavigate: ((Int) -> Void)? = nil) {
        self.input = input
        self.navigationTick = navigationTick
        self.overlay = overlay
        self.practiceHandMode = practiceHandMode
        self.navigationRange = navigationRange
        self.onNavigate = onNavigate
    }

    public var body: some View {
        Group {
            if let plan = owner.plan, plan.input == input {
                if let tick = navigationTick, let target = plan.spreadIndex(containingTick: tick) {
                    GrandStaffNotationSpreadView(plan: plan, targetIndex: target, overlay: overlay, practiceHandMode: practiceHandMode,
                        onTurnBackward: navigationAction(plan: plan, target: target - 1),
                        onTurnForward: navigationAction(plan: plan, target: target + 1))
                } else {
                    ContentUnavailableView("没有有效练习位置", systemImage: "music.note")
                }
            } else if let failure = owner.failureMessage {
                ContentUnavailableView("曲谱排版失败", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ProgressView("正在排版乐谱")
            }
        }
        .task(id: input) { await owner.load(input) }
        .onDisappear { owner.clear() }
    }

    private func navigationAction(plan: GrandStaffNotationPagePlan, target: Int) -> (() -> Void)? {
        guard let onNavigate, let tick = plan.navigationTick(forSpread: target, within: navigationRange) else { return nil }
        return { onNavigate(tick) }
    }
}
