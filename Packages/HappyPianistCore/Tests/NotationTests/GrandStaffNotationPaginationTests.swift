import Foundation
@testable import MusicXML
@testable import Notation
import Practice
import Testing

@Test
func paginationCoversEveryOccurrenceIncludingEmptyRestsAndHalfOpenBoundaries() throws {
    let score = try paginationFixture(count: 24)
    let plan = try GrandStaffNotationPaginationService().makePlan(score: score)
    let measures = plan.pages.flatMap(\.measures)
    #expect(measures.map(\.span.occurrenceID) == score.input.measureSpans.map(\.occurrenceID))
    #expect(Set(measures.map(\.span.occurrenceID)).count == 24)
    #expect(plan.pages.contains { $0.systems.count > 1 })
    #expect(measures.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    for page in plan.pages {
        for measure in page.measures {
            #expect(plan.pageIndex(containingTick: measure.span.startTick) == page.index)
            #expect(plan.pageIndex(containingTick: measure.span.endTick - 1) == page.index)
            #expect(plan.spreadIndex(containing: measure.span.occurrenceID) == page.index / 2)
            let location = try #require(plan.location(containing: measure.span.occurrenceID))
            #expect(plan.location(containingTick: measure.span.startTick) == location)
            #expect(page.systems.contains { $0.id == location.systemID && $0.measures.contains(measure.span) })
        }
    }
    #expect(plan.pageIndex(containingTick: -1) == nil)
    let endTick = try #require(score.input.measureSpans.last?.endTick)
    #expect(plan.pageIndex(containingTick: endTick + 1) == nil)
    #expect(plan.pageIndex(containingTick: endTick) == plan.pages.count - 1)
    #expect(plan.spreadCount == (plan.pages.count + 1) / 2)
}

@Test
func paginationDoesNotChangeForOverlayHandOrHostAndCanvasUsesMeasuredInk() throws {
    let score = try paginationFixture(count: 24)
    let plan = try GrandStaffNotationPaginationService().makePlan(score: score)
    for page in plan.pages {
        var occupied = 0.0
        for system in page.systems {
            occupied += system.rect.height * system.scale
            for spacing in [4.0, 11, 22, 40] {
                for hand in [PracticeHandMode.both, .left, .right] {
                    let presentation = GrandStaffNotationPresentationViewModel().makePresentation(system: system, staffSpace: spacing, projection: score.input.projection, overlay: .init(activeEventIDs: [], activeTickRange: 1920..<3840), practiceHandMode: hand)
                    #expect(abs(Double(presentation.canvasLayout.lineSpacing) - spacing * system.scale) < 0.000001)
                    #expect(abs(Double(presentation.canvasLayout.size.height) - system.rect.height * spacing * system.scale) < 0.000001)
                    #expect(presentation.notationLayout.rests.count == system.notation.rests.count)
                    #expect(presentation.notationLayout.attributeChanges.allSatisfy { $0.tick != system.measures.first?.startTick })
                }
            }
        }
        occupied += Double(max(0, page.systems.count - 1)) * plan.geometry.systemGap
        #expect(occupied <= plan.geometry.contentHeight + 0.00001)
    }
    #expect(try GrandStaffNotationPaginationService().makePlan(score: score) == plan)
}

@Test
func sourceBeamComponentCannotBeSplitAndOversizedSystemOwnsPage() throws {
    let notes = (0..<40).map { index in
        "<note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>1024th</type><beam number=\"1\">\(index == 0 ? "begin" : index == 39 ? "end" : "continue")</beam></note>" + (index == 19 ? "</measure><measure number=\"2\">" : "")
    }.joined()
    let score = try paginationFixture(count: 2, measures: "<measure number=\"1\"><attributes><divisions>256</divisions><staves>2</staves></attributes>\(notes)</measure>")
    let plan = try GrandStaffNotationPaginationService().makePlan(score: score)
    let system = try #require(plan.pages.first?.systems.first)
    #expect(plan.pages.count == 1)
    #expect(system.measures.count == 2)
    #expect(system.notation.items.count == 40)
    #expect(system.scale < 1)
    #expect(system.rect.width * system.scale <= 46 + 0.00001)
    #expect(system.rect.height * system.scale <= 61.5 + 0.00001)
    #expect(system.notation.beams.first?.chordIDs.count == 40)
}

@Test
func localStaffContextAndSignatureInkUseSameClefAndSevenKeyGeometry() throws {
    let score = try paginationFixture(count: 1, measures: """
    <measure number="1"><attributes><divisions>1</divisions><staves>2</staves>
    <key number="1"><fifths>7</fifths></key><key number="2"><fifths>-7</fifths></key>
    <time number="1"><beats>3</beats><beat-type>4</beat-type></time><time number="2"><beats>6</beats><beat-type>8</beat-type></time>
    <clef number="1"><sign>C</sign><line>3</line></clef><clef number="2"><sign>G</sign><line>2</line></clef></attributes>
    <note><pitch><step>C</step><octave>4</octave></pitch><duration>3</duration><type>half</type><dot/><staff>1</staff></note></measure>
    """)
    let context = GrandStaffNotationContextResolver().context(input: score.input, tick: 0)
    #expect(context.treble.clefSign == "C")
    #expect(context.treble.fifths == 7)
    #expect(context.bass.fifths == -7)
    #expect(context.treble.meter == "3/4")
    #expect(context.bass.meter == "6/8")
    let plan = try GrandStaffNotationPaginationService().makePlan(score: score)
    let system = try #require(plan.pages.first?.systems.first)
    #expect(system.notation.attributeChanges.isEmpty)
    #expect(system.header.glyphs.filter { $0.token == .accidentalSharp }.count == 7)
    #expect(system.header.glyphs.filter { $0.token == .accidentalFlat }.count == 7)
    #expect(system.musicOriginX > system.header.bounds.maxX)
}

@Test
func oversizedBeamPageDoesNotShareSpaceWithPrecedingNormalSystem() throws {
    let notes = (0..<40).map { index in
        "<note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>1024th</type><beam number=\"1\">\(index == 0 ? "begin" : index == 39 ? "end" : "continue")</beam></note>" + (index == 19 ? "</measure><measure number=\"3\">" : "")
    }.joined()
    let score = try paginationFixture(count: 3, measures: "<measure number=\"1\"><attributes><divisions>256</divisions><staves>2</staves></attributes><note><rest measure=\"yes\"/><duration>1024</duration></note></measure><measure number=\"2\">\(notes)</measure>")
    let plan = try GrandStaffNotationPaginationService().makePlan(score: score)
    #expect(plan.pages.count == 2)
    #expect(plan.pages.allSatisfy { $0.systems.count == 1 })
    #expect(plan.pages.first?.systems.first?.scale == 1)
    #expect((plan.pages.last?.systems.first?.scale ?? 1) < 1)
}

@Test
func paginationKeepsSpannerPitchAnchorsAndEndingContinuationAcrossSystems() throws {
    let bars = (1...8).map { measure in
        let notes = (0..<16).map { index in
            let tie = measure == 1 && index == 15 ? "<tied type=\"start\"/>" : measure == 2 && index == 0 ? "<tied type=\"stop\"/>" : ""
            let spans = measure == 1 && index == 0 ? "<slur type=\"start\" number=\"1\"/><tuplet type=\"start\" number=\"1\" bracket=\"yes\"/><tuplet type=\"start\" number=\"2\" bracket=\"yes\"/>" : measure == 8 && index == 15 ? "<slur type=\"stop\" number=\"1\"/><tuplet type=\"stop\" number=\"2\"/><tuplet type=\"stop\" number=\"1\"/>" : ""
            return "<note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type><notations>\(tie)\(spans)</notations></note>"
        }.joined()
        let opening = measure == 1 ? "<attributes><divisions>1</divisions><staves>2</staves><time><beats>16</beats><beat-type>4</beat-type></time></attributes><barline location=\"left\"><ending number=\"1\" type=\"start\"/></barline>" : ""
        let closing = measure == 3 ? "<barline location=\"right\"><ending number=\"1\" type=\"stop\"/><repeat direction=\"backward\"/></barline>" : ""
        return "<measure number=\"\(measure)\">\(opening)\(notes)\(closing)</measure>"
    }.joined()
    let score = try paginationFixture(count: 8, measures: bars)
    let plan = try GrandStaffNotationPaginationService().makePlan(score: score)
    let systems = plan.pages.flatMap(\.systems)
    #expect(systems.count >= 4)
    for system in systems {
        for slur in system.notation.slurs {
            for identifier in [slur.startOccurrenceID, slur.endOccurrenceID] {
                let identifier = try #require(identifier)
                let original = try #require(score.notation.items.first { $0.id == identifier })
                let anchor = try #require(system.notation.spannerAnchors[identifier])
                #expect(anchor.staffStep == original.staffStep)
                #expect(anchor.staffNumber == original.staffNumber)
            }
        }
        #expect(system.notation.tuplets.count == 2)
        #expect(Set(system.notation.tuplets.map(\.nestingLevel)).count == 2)
        if system.scale < 1 {
            #expect(plan.pages.first { $0.systems.contains { $0.id == system.id } }?.systems.count == 1)
        }
    }
    #expect(systems.dropFirst().contains { $0.notation.ties.contains { $0.continuesFromPrevious } })
    #expect(systems.dropFirst().contains { $0.notation.marks.contains { $0.kind == .endingStart && $0.continuesFromPrevious } })
    let afterEnding = systems.filter { ($0.measures.first?.sourceMeasureIndex ?? 0) > 3 }
    #expect(afterEnding.allSatisfy { !$0.notation.marks.contains { $0.kind == .endingStart } })
}

@Test
func additiveAndUnmeteredSignaturesRemainExplicitInsteadOfDroppingSymbols() {
    for meter in ["3+2/8", "3/4 + 2/4", "senza misura"] {
        let signature = GrandStaffNotationSignatureLayout.make(staff: .init(clefSign: "G", clefLine: 2, meter: meter), staffNumber: 1)
        #expect(signature.labels.contains { $0.text == meter })
        #expect(signature.labels.allSatisfy { signature.bounds.contains($0.bounds) })
        #expect(signature.width > signature.bounds.maxX)
    }
}

private func paginationFixture(count: Int, measures: String? = nil) throws -> GrandStaffNotationScoreLayout {
    let bars = measures ?? (1...count).map { index in
        "<measure number=\"\(index)\">\(index == 1 ? "<attributes><divisions>1</divisions><staves>2</staves><time><beats>4</beats><beat-type>4</beat-type></time></attributes>" : "")<note><rest measure=\"yes\"/><duration>4</duration><staff>1</staff></note></measure>"
    }.joined()
    let xml = "<score-partwise><part-list><score-part id=\"P1\"><part-name>Piano</part-name></score-part></part-list><part id=\"P1\">\(bars)</part></score-partwise>"
    let parsed = try MusicXMLParser().parse(data: Data(xml.utf8))
    let projection = ScoreNotationProjection(plan: makeTestScorePerformancePlan(from: parsed), sourceScore: parsed)
    let fixture = try makeNotationScoreFixture(projection: projection, measureSpans: parsed.measures)
    let input = GrandStaffNotationScoreInput(identity: fixture.input.identity, projection: projection, measureSpans: parsed.measures, facts: fixture.input.facts, attributeTimeline: MusicXMLAttributeTimeline(timeSignatureEvents: parsed.timeSignatureEvents, keySignatureEvents: parsed.keySignatureEvents, clefEvents: parsed.clefEvents))
    return try GrandStaffNotationScoreLayoutService().makeLayout(input: input)
}
