import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func despacitoFixtureBuildsGuidesWithGapAndRetrigger() throws {
    let fixtureURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "DESPACITOHighlightRegression.musicxml")

    let score = try MusicXMLParser().parse(fileURL: fixtureURL)
    let expressivity = MusicXMLExpressivityOptions()
    let steps = PracticeStepBuilder().buildSteps(from: score, expressivity: expressivity).steps
    let spans = MusicXMLNoteSpanBuilder().buildSpans(from: score.notes, expressivity: expressivity)

    let guides = PianoHighlightGuideBuilderService().buildGuides(
        input: PianoHighlightGuideBuildInput(score: score, steps: steps, noteSpans: spans, expressivity: expressivity)
    )

    let c4Triggers = guides.filter { guide in
        guide.kind == .trigger && guide.triggeredNotes.contains(where: { $0.midiNote == 60 })
    }
    #expect(c4Triggers.count == 2)
    #expect(Set(c4Triggers.map(\.tick)) == [0, 720])

    let gapOrRelease = guides.first { guide in
        guide.tick == 480 && (guide.kind == .gap || guide.kind == .release)
    }
    #expect(gapOrRelease?.releasedMIDINotes.contains(60) == true)
    #expect(gapOrRelease?.highlightedMIDINotes.contains(60) == false)

    let chordTrigger = guides.first { guide in
        guide.kind == .trigger && guide.tick == 720
    }
    #expect(chordTrigger?.highlightedMIDINotes == [60, 64])

    let g4Triggers = guides.filter { guide in
        guide.kind == .trigger && guide.triggeredNotes.contains(where: { $0.midiNote == 67 })
    }
    #expect(g4Triggers.count == 1)
}

