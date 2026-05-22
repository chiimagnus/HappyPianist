@testable import LonelyPianistAVP
import Testing

@Test
func parsedElementCoverageClassifiesAllKnownNoteEventFields() {
    let fields = Set(PianoHighlightParsedElementCoverageService().noteEventCoverages().map(\.field))
    let expected: Set = [
        "MusicXMLNoteEvent.partID",
        "MusicXMLNoteEvent.measureNumber",
        "MusicXMLNoteEvent.tick",
        "MusicXMLNoteEvent.durationTicks",
        "MusicXMLNoteEvent.midiNote",
        "MusicXMLNoteEvent.isRest",
        "MusicXMLNoteEvent.isChord",
        "MusicXMLNoteEvent.isGrace",
        "MusicXMLNoteEvent.graceSlash",
        "MusicXMLNoteEvent.graceStealTimePrevious",
        "MusicXMLNoteEvent.graceStealTimeFollowing",
        "MusicXMLNoteEvent.tieStart",
        "MusicXMLNoteEvent.tieStop",
        "MusicXMLNoteEvent.staff",
        "MusicXMLNoteEvent.voice",
        "MusicXMLNoteEvent.attackTicks",
        "MusicXMLNoteEvent.releaseTicks",
        "MusicXMLNoteEvent.dynamicsOverrideVelocity",
        "MusicXMLNoteEvent.articulations",
        "MusicXMLNoteEvent.arpeggiate",
        "MusicXMLNoteEvent.fingeringText",
    ]
    #expect(fields == expected)
}

@Test
func parsedElementCoverageClassifiesScoreAndSpanFields() {
    let service = PianoHighlightParsedElementCoverageService()
    let coverages = service.scoreCoverages() + service.noteSpanCoverages()
    let fields = Set(coverages.map(\.field))
    let expected: Set = [
        "MusicXMLScore.notes",
        "MusicXMLScore.tempoEvents",
        "MusicXMLScore.soundDirectives",
        "MusicXMLScore.pedalEvents",
        "MusicXMLScore.dynamicEvents",
        "MusicXMLScore.wedgeEvents",
        "MusicXMLScore.fermataEvents",
        "MusicXMLScore.slurEvents",
        "MusicXMLScore.timeSignatureEvents",
        "MusicXMLScore.keySignatureEvents",
        "MusicXMLScore.clefEvents",
        "MusicXMLScore.wordsEvents",
        "MusicXMLScore.measures",
        "MusicXMLScore.repeatDirectives",
        "MusicXMLScore.endingDirectives",
        "MusicXMLNoteSpan.midiNote",
        "MusicXMLNoteSpan.staff",
        "MusicXMLNoteSpan.voice",
        "MusicXMLNoteSpan.onTick",
        "MusicXMLNoteSpan.offTick",
    ]
    #expect(fields == expected)
    #expect(coverages.allSatisfy { $0.reason.isEmpty == false })
}
