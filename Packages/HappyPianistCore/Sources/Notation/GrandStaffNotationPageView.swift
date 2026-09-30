import Practice
import SwiftUI

struct GrandStaffNotationPageView: View {
    let plan: GrandStaffNotationPagePlan
    let index: Int
    let staffSpace: Double
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode

    var body: some View {
        let geometry = plan.geometry
        let page = plan.pages.indices.contains(index) ? plan.pages[index] : nil
        VStack(alignment: .leading, spacing: 0) {
            if let page {
                Text("第 \(index + 1) 页 / \(plan.pages.count)")
                    .font(.system(size: 1.3 * staffSpace))
                    .frame(height: 3 * staffSpace, alignment: .topLeading)
                VStack(alignment: .leading, spacing: geometry.systemGap * staffSpace) {
                    ForEach(page.systems) { system in
                        GrandStaffNotationSystemView(system: system, plan: plan, staffSpace: staffSpace, overlay: overlay, practiceHandMode: practiceHandMode)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(geometry.margin * staffSpace)
        .frame(width: geometry.width * staffSpace, height: geometry.height * staffSpace, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if let page, let range = overlay.activeTickRange {
                ForEach(page.measures.filter { range.overlaps($0.span.startTick..<$0.span.endTick) }, id: \.span.id) { measure in
                    Rectangle()
                        .strokeBorder(.black.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: measure.rect.width * staffSpace, height: measure.rect.height * staffSpace)
                        .position(x: measure.rect.midX * staffSpace, y: measure.rect.midY * staffSpace)
                        .accessibilityHidden(true)
                }
            }
        }
        .foregroundStyle(.black)
        .background(Color(red: 0.98, green: 0.965, blue: 0.92))
        .environment(\.colorScheme, .light)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(page == nil ? "" : "第 \(index + 1) 页，共 \(plan.pages.count) 页")
        .accessibilityHidden(page == nil)
    }
}
