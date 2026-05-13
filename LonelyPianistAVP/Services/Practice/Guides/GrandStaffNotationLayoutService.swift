import Foundation

struct GrandStaffNotationLayoutService {
    func makeLayout(
        guides: [PianoHighlightGuide],
        currentGuide: PianoHighlightGuide?,
        measureSpans: [MusicXMLMeasureSpan] = [],
        context: GrandStaffNotationContext? = nil,
        halfWindowTicks: Int = 1_920,
        scrollTick: Double? = nil
    ) -> GrandStaffNotationLayout {
        _ = guides
        _ = currentGuide
        _ = measureSpans
        _ = halfWindowTicks
        _ = scrollTick

        return GrandStaffNotationLayout(
            items: [],
            chords: [],
            rests: [],
            barlines: [],
            beams: [],
            context: context
        )
    }
}

