import Practice
import SwiftUI

public struct GrandStaffNotationSpreadView: View {
    let plan: GrandStaffNotationPagePlan
    let targetIndex: Int
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var enlarged = false

    public init(plan: GrandStaffNotationPagePlan, targetIndex: Int, overlay: ScoreNotationProjection.Overlay = .empty, practiceHandMode: PracticeHandMode = .both) {
        self.plan = plan
        self.targetIndex = targetIndex
        self.overlay = overlay
        self.practiceHandMode = practiceHandMode
    }

    public var body: some View {
        GeometryReader { geometry in
            let magnified = enlarged || dynamicTypeSize.isAccessibilitySize
            let staffSpace = min(geometry.size.width / plan.geometry.spreadWidth, geometry.size.height / plan.geometry.height)
            if (0..<plan.spreadCount).contains(targetIndex) {
                if magnified {
                    ScrollView(.vertical) {
                        VStack(spacing: plan.geometry.gutter * geometry.size.width / plan.geometry.width) {
                            ForEach(targetIndex * 2..<min(targetIndex * 2 + 2, plan.pages.count), id: \.self) { index in
                                GrandStaffNotationPageView(plan: plan, index: index, staffSpace: geometry.size.width / plan.geometry.width, overlay: overlay, practiceHandMode: practiceHandMode)
                            }
                        }
                    }
                } else {
                    HStack(spacing: plan.geometry.gutter * staffSpace) {
                        GrandStaffNotationPageView(plan: plan, index: targetIndex * 2, staffSpace: staffSpace, overlay: overlay, practiceHandMode: practiceHandMode)
                        GrandStaffNotationPageView(plan: plan, index: targetIndex * 2 + 1, staffSpace: staffSpace, overlay: overlay, practiceHandMode: practiceHandMode)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("曲谱位置无效", systemImage: "music.note")
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(enlarged ? "恢复双页" : "放大阅读", systemImage: enlarged ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { enlarged.toggle() }
                .labelStyle(.iconOnly)
                .padding(.trailing)
        }
    }
}

public struct GrandStaffNotationBookView: View {
    let input: GrandStaffNotationScoreInput
    let navigationTick: Int?
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    @State private var owner = GrandStaffNotationPageViewModel()

    public init(input: GrandStaffNotationScoreInput, navigationTick: Int?, overlay: ScoreNotationProjection.Overlay = .empty, practiceHandMode: PracticeHandMode = .both) {
        self.input = input
        self.navigationTick = navigationTick
        self.overlay = overlay
        self.practiceHandMode = practiceHandMode
    }

    public var body: some View {
        Group {
            if let plan = owner.plan, plan.input == input {
                if let tick = navigationTick, let target = plan.spreadIndex(containingTick: tick) {
                    GrandStaffNotationSpreadView(plan: plan, targetIndex: target, overlay: overlay, practiceHandMode: practiceHandMode)
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
}
