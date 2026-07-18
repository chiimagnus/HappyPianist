import SwiftUI

struct GrandStaffNotationView: View {
    let projection: ScoreNotationProjection
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    let practiceHandMode: PracticeHandMode
    let tickRange: Range<Int>?
    var scrollTickProvider: (() -> Double?)?

    private let fixedLineSpacing: CGFloat = 14
    private let presentationViewModel: GrandStaffNotationPresentationViewModel
    private let renderer: GrandStaffNotationRenderer

    @Environment(\.displayScale) private var displayScale
    @State private var centeredForFirstOccurrenceID: String?

    init(
        projection: ScoreNotationProjection,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        practiceHandMode: PracticeHandMode = .both,
        tickRange: Range<Int>? = nil,
        scrollTickProvider: (() -> Double?)? = nil,
        layoutService: GrandStaffNotationLayoutService = GrandStaffNotationLayoutService(),
        viewportLayoutService: GrandStaffNotationViewportLayoutService = GrandStaffNotationViewportLayoutService(),
        renderer: GrandStaffNotationRenderer = GrandStaffNotationRenderer()
    ) {
        self.projection = projection
        self.measureSpans = measureSpans
        self.context = context
        self.practiceHandMode = practiceHandMode
        self.tickRange = tickRange
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
            let presentation = presentationViewModel.makePresentation(
                size: proxy.size,
                lineSpacing: fixedLineSpacing,
                projection: projection,
                measureSpans: measureSpans,
                context: context,
                practiceHandMode: practiceHandMode,
                tickRange: tickRange,
                scrollTick: scrollTickProvider?()
            )
            let viewportLayout = presentation.viewportLayout

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            renderer.draw(
                                presentation: presentation,
                                in: context,
                                displayScale: displayScale
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
                    }
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
        .accessibilityLabel("Grand Staff 五线谱")
    }

    private enum DefaultScrollAnchorID {
        static let value = "grandstaff-default-anchor"
    }

    private var firstVisibleOccurrenceID: String? {
        projection.performedOccurrences.first {
            tickRange?.contains($0.writtenOnTick) ?? true
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

#Preview("Grand Staff") {
    GrandStaffNotationView(
        projection: .empty,
        measureSpans: [],
        context: GrandStaffNotationContext()
    )
    .frame(width: 800, height: 300)
    .padding()
}
