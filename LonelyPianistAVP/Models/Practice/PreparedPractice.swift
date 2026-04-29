import Foundation

struct PreparedPractice {
    let steps: [PracticeStep]
    let file: ImportedMusicXMLFile
    let tempoMap: MusicXMLTempoMap
    let pedalTimeline: MusicXMLPedalTimeline?
    let fermataTimeline: MusicXMLFermataTimeline?
    let attributeTimeline: MusicXMLAttributeTimeline?
    let slurTimeline: MusicXMLSlurTimeline?
    let noteSpans: [MusicXMLNoteSpan]
    let highlightGuides: [PianoHighlightGuide]
    let measureSpans: [MusicXMLMeasureSpan]
    let unsupportedNoteCount: Int
}
