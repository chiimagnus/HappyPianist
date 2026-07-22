import SwiftUI

struct GrandStaffNotationView: View {
    let projection: ScoreNotationProjection
    let overlay: ScoreNotationProjection.Overlay
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    let practiceHandMode: PracticeHandMode
    var scrollTickProvider: (() -> Double?)?

    @ScaledMetric(relativeTo: .body) private var lineSpacing: CGFloat = 14
    private let presentationViewModel: GrandStaffNotationPresentationViewModel
    private let renderer: GrandStaffNotationRenderer

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var centeredForFirstOccurrenceID: String?

    init(
        projection: ScoreNotationProjection,
        overlay: ScoreNotationProjection.Overlay = .empty,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        practiceHandMode: PracticeHandMode = .both,
        scrollTickProvider: (() -> Double?)? = nil,
        layoutService: GrandStaffNotationLayoutService = GrandStaffNotationLayoutService(),
        viewportLayoutService: GrandStaffNotationViewportLayoutService = GrandStaffNotationViewportLayoutService(),
        renderer: GrandStaffNotationRenderer = GrandStaffNotationRenderer()
    ) {
        self.projection = projection
        self.overlay = overlay
        self.measureSpans = measureSpans
        self.context = context
        self.practiceHandMode = practiceHandMode
        self.scrollTickProvider = scrollTickProvider
        presentationViewModel = GrandStaffNotationPresentationViewModel(
            layoutService: layoutService,
            viewportLayoutService: viewportLayoutService
        )
        self.renderer = renderer
    }

    var body: some View {
        // KEEP_GEOMETRYREADER: needs exact viewport size for notation layout + scroll anchoring.
        GeometryReader { proxy in
            let scrollTick = scrollTickProvider?()
            let presentation = presentationViewModel.makePresentation(
                size: proxy.size,
                lineSpacing: lineSpacing,
                projection: projection,
                overlay: overlay,
                measureSpans: measureSpans,
                context: context,
                practiceHandMode: practiceHandMode,
                scrollTick: scrollTick
            )
            let viewportLayout = presentation.viewportLayout
            let accessibility = GrandStaffNotationAccessibilityDescriptor.make(
                projection: projection,
                layout: presentation.notationLayout,
                measureSpans: measureSpans,
                currentTick: scrollTick
            )

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            renderer.draw(
                                presentation: presentation,
                                in: context,
                                displayScale: displayScale,
                                differentiateWithoutColor: differentiateWithoutColor
                            )
                        }
                        .frame(width: proxy.size.width, height: viewportLayout.requiredHeight)

                        VStack(spacing: 0) {
                            Color.clear.frame(height: presentation.defaultScrollAnchorY)
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id(DefaultScrollAnchorID.value)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 1, height: viewportLayout.requiredHeight, alignment: .top)

                        GrandStaffNotationAccessibilityOverlay(descriptor: accessibility)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibility.containerLabel)
                    .accessibilityValue(accessibility.containerValue)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    centerIfNeeded(
                        firstOccurrenceID: firstVisibleOccurrenceID,
                        scrollProxy: scrollProxy
                    )
                }
                .onChange(of: firstVisibleOccurrenceID) {
                    centerIfNeeded(
                        firstOccurrenceID: firstVisibleOccurrenceID,
                        scrollProxy: scrollProxy
                    )
                }
            }
        }
    }

    private enum DefaultScrollAnchorID {
        static let value = "grandstaff-default-anchor"
    }

    private var firstVisibleOccurrenceID: String? {
        projection.performedOccurrences.first {
            overlay.activeTickRange?.contains($0.writtenOnTick) ?? true
        }?.id.description
    }

    private func centerIfNeeded(firstOccurrenceID: String?, scrollProxy: ScrollViewProxy) {
        guard centeredForFirstOccurrenceID != firstOccurrenceID else { return }
        centeredForFirstOccurrenceID = firstOccurrenceID
        Task { @MainActor in
            await Task.yield()
            scrollProxy.scrollTo(DefaultScrollAnchorID.value, anchor: .center)
        }
    }
}

struct GrandStaffNotationAccessibilityDescriptor: Equatable {
    struct Element: Equatable, Identifiable {
        let id: String
        let label: String
    }

    let containerLabel: String
    let containerValue: String
    let elements: [Element]

    static func make(
        projection: ScoreNotationProjection,
        layout: GrandStaffNotationLayout,
        measureSpans: [MusicXMLMeasureSpan],
        currentTick: Double?
    ) -> Self {
        let occurrencesByID = Dictionary(
            uniqueKeysWithValues: projection.performedOccurrences.map { ($0.id.description, $0) }
        )
        let sourceNotesByID = Dictionary(uniqueKeysWithValues: projection.sourceNotes.map { ($0.id, $0) })
        let fallbacksBySourceID = Dictionary(grouping: projection.fallbacks, by: \.sourceID)

        func source(for occurrenceID: String) -> ScoreNotationProjection.SourceNote? {
            occurrencesByID[occurrenceID].flatMap { sourceNotesByID[$0.sourceNoteID] }
        }

        func unsupportedDescription(for occurrenceID: String) -> String? {
            guard let source = source(for: occurrenceID),
                  let fallback = fallbacksBySourceID[source.id]?.first
            else { return nil }
            return switch fallback.placeholderPolicy {
            case .omit: "不支持的记谱内容，已省略图形"
            case .reserveRhythmicSpace: "不支持的记谱内容，已保留节奏占位"
            }
        }

        let notes = layout.items.sorted(by: elementOrder).map { item in
            let sourceNote = source(for: item.occurrenceID)
            var components = [staffDescription(item.staffNumber)]
            if let pitch = pitchDescription(sourceNote) { components.append(pitch) }
            components.append("音符")
            if item.isHighlighted { components.append("当前高亮") }
            if let fingering = item.fingerings.fingeringDisplayText {
                components.append("指法 \(fingering)")
            }
            if let unsupported = unsupportedDescription(for: item.occurrenceID) {
                components.append(unsupported)
            }
            return Element(id: "note:\(item.id)", label: components.joined(separator: "，"))
        }
        let rests = layout.rests.sorted(by: elementOrder).map { rest in
            var components = [staffDescription(rest.staffNumber), "休止符"]
            if rest.isHighlighted { components.append("当前高亮") }
            if let unsupported = unsupportedDescription(for: rest.id) {
                components.append(unsupported)
            }
            return Element(id: "rest:\(rest.id)", label: components.joined(separator: "，"))
        }

        let resolvedTick = currentTick.flatMap {
            guard $0.isFinite, $0 >= Double(Int.min), $0 <= Double(Int.max) else { return nil }
            return Int($0)
        }
            ?? layout.items.first?.tick
            ?? layout.rests.first?.tick
            ?? 0
        let currentMeasure = measureSpans.first {
            $0.startTick <= resolvedTick && resolvedTick < $0.endTick
        } ?? measureSpans.last(where: { $0.startTick <= resolvedTick })
        let measurePrefix = currentMeasure.map {
            "第 \($0.sourceMeasureNumberToken ?? $0.measureNumber.formatted()) 小节"
        } ?? "当前窗口"

        return Self(
            containerLabel: "Grand Staff 五线谱",
            containerValue: "\(measurePrefix)，\(notes.count) 个音符，\(rests.count) 个休止符",
            elements: notes + rests
        )
    }

    private static func staffDescription(_ staffNumber: Int) -> String {
        staffNumber >= 2 ? "下谱表" : "上谱表"
    }

    private static func pitchDescription(_ source: ScoreNotationProjection.SourceNote?) -> String? {
        guard let pitch = source?.writtenPitch else { return nil }
        return "\(pitch.step)\(pitch.octave)"
    }

    private static func elementOrder(_ lhs: GrandStaffNotationItem, _ rhs: GrandStaffNotationItem) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
        if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
        return lhs.id < rhs.id
    }

    private static func elementOrder(_ lhs: GrandStaffNotationRest, _ rhs: GrandStaffNotationRest) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
        if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
        return lhs.id < rhs.id
    }
}

private struct GrandStaffNotationAccessibilityOverlay: View {
    let descriptor: GrandStaffNotationAccessibilityDescriptor

    var body: some View {
        VStack(spacing: 0) {
            ForEach(descriptor.elements) { element in
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(element.label)
            }
        }
        .frame(width: 1, height: 1, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

#Preview("Grand Staff") {
    GrandStaffNotationView(
        projection: .empty,
        measureSpans: [],
        context: GrandStaffNotationContext()
    )
    .frame(width: 800, height: 300)
    .padding()
}
