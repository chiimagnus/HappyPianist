import Practice
import SwiftUI

struct GrandStaffNotationPageView: View {
    let plan: GrandStaffNotationPagePlan
    let index: Int
    let staffSpace: Double
    let overlay: ScoreNotationProjection.Overlay
    let practiceHandMode: PracticeHandMode
    var annotations: [GrandStaffNotationMeasureAnnotation] = []

    var body: some View {
        let geometry = plan.geometry
        let page = plan.pages.indices.contains(index) ? plan.pages[index] : nil
        VStack(alignment: .leading, spacing: 0) {
            if let page {
                Text("第 \(index + 1) 页 / \(plan.pages.count)")
                    .font(.caption)
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
                }
            }
        }
        .foregroundStyle(.black)
        .overlay(alignment: .topLeading) {
            if let page {
                ForEach(page.measures, id: \.span.id) { measure in
                    if let annotation = annotations.first(where: { $0.occurrenceID == measure.span.occurrenceID }) {
                        HStack(spacing: 0.3 * staffSpace) {
                            Image(systemName: annotation.state.symbol)
                            if annotation.isResume { Image(systemName: "bookmark") }
                            if annotation.isFocus { Image(systemName: "scope") }
                        }
                        .font(.caption2)
                        .foregroundStyle(.black)
                        .frame(width: measure.rect.width * staffSpace, alignment: .leading)
                        .position(x: measure.rect.midX * staffSpace, y: (measure.rect.minY - 0.8) * staffSpace)
                    }
                }
            }
        }
        .background(Color(red: 0.98, green: 0.965, blue: 0.92))
        .environment(\.colorScheme, .light)
        .environment(\.layoutDirection, .leftToRight)
    }
}
