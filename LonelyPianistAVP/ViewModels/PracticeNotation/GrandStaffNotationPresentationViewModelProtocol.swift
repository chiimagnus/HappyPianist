import CoreGraphics

protocol GrandStaffNotationPresentationViewModelProtocol {
    func makePresentation(
        size: CGSize,
        lineSpacing: CGFloat,
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        scrollTick: Double?
    ) -> GrandStaffNotationPresentation
}
