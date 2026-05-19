import SwiftUI

struct GrandStaffNotationView: View {
    let guides: [PianoHighlightGuide]
    let currentGuide: PianoHighlightGuide?
    let measureSpans: [MusicXMLMeasureSpan]
    let context: GrandStaffNotationContext?
    var scrollTickProvider: (() -> Double?)?

    private let fixedLineSpacing: CGFloat = 14
    private let presentationViewModel: any GrandStaffNotationPresentationViewModelProtocol
    private let renderer: any GrandStaffNotationRendererProtocol

    @Environment(\.displayScale) private var displayScale
    @State private var centeredForFirstGuideID: Int?

    init(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        scrollTickProvider: (() -> Double?)? = nil,
        layoutService: any GrandStaffNotationLayoutServiceProtocol = GrandStaffNotationLayoutService(),
        viewportLayoutService: any GrandStaffNotationViewportLayoutServiceProtocol = GrandStaffNotationViewportLayoutService(),
        renderer: any GrandStaffNotationRendererProtocol = GrandStaffNotationRenderer()
    ) {
        self.guides = guides
        self.currentGuide = currentGuide
        self.measureSpans = measureSpans
        self.context = context
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
                guides: guides,
                currentGuide: currentGuide,
                measureSpans: measureSpans,
                context: context,
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
                    centerIfNeeded(firstGuideID: guides.first?.id, scrollProxy: scrollProxy)
                }
                .onChange(of: guides.first?.id) {
                    centerIfNeeded(firstGuideID: guides.first?.id, scrollProxy: scrollProxy)
                }
            }
        }
        .accessibilityLabel("Grand Staff 五线谱")
    }

    private enum DefaultScrollAnchorID {
        static let value = "grandstaff-default-anchor"
    }

    private func centerIfNeeded(firstGuideID: Int?, scrollProxy: ScrollViewProxy) {
        guard centeredForFirstGuideID != firstGuideID else { return }
        centeredForFirstGuideID = firstGuideID
        Task { @MainActor in
            await Task.yield()
            scrollProxy.scrollTo(DefaultScrollAnchorID.value, anchor: .center)
        }
    }
}

#Preview("Grand Staff") {
    GrandStaffNotationView(
        guides: [],
        currentGuide: nil,
        measureSpans: [],
        context: GrandStaffNotationContext()
    )
    .frame(width: 800, height: 300)
    .padding()
}
