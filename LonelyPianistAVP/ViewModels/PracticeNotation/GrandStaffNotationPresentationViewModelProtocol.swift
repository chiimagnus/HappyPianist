import CoreGraphics

protocol GrandStaffNotationPresentationViewModelProtocol {
    func makePresentation(
        size: CGSize,
        lineSpacing: CGFloat,
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        practiceHandMode: PracticeHandMode,
        scrollTick: Double?
    ) -> GrandStaffNotationPresentation
}
