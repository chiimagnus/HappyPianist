@testable import HappyPianistAVP
import Testing

@Test
func layoutAssignsItemsToTrebleAndBassStaves() {
    let guides = [
        PianoHighlightGuide(
            id: 1,
            kind: .trigger,
            tick: 0,
            durationTicks: 480,
            practiceStepIndex: 0,
            activeNotes: [],
            triggeredNotes: [
                PianoHighlightNote(
                    occurrenceID: "n1",
                    midiNote: 60,
                    staff: 1,
                    voice: 1,
                    velocity: 96,
                    onTick: 0,
                    offTick: 480,
                    fingeringText: nil
                ),
                PianoHighlightNote(
                    occurrenceID: "n2",
                    midiNote: 48,
                    staff: 2,
                    voice: 1,
                    velocity: 96,
                    onTick: 0,
                    offTick: 480,
                    fingeringText: nil
                ),
            ],
            releasedMIDINotes: []
        ),
    ]

    let layout = GrandStaffNotationLayoutService().makeLayout(
        guides: guides,
        currentGuide: guides[0]
    )

    #expect(layout.items.count == 2)
    #expect(Set(layout.items.map(\.staffNumber)) == [1, 2])
}

@Test
func layoutEmitsBarlinesForMeasureSpansStartAndEndTicks() {
    let measureSpans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, sourceMeasureIndex: 1, sourceMeasureNumberToken: "1", occurrenceIndex: 0, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, sourceMeasureIndex: 2, sourceMeasureNumberToken: "2", occurrenceIndex: 1, startTick: 480, endTick: 960),
    ]

    let layout = GrandStaffNotationLayoutService().makeLayout(
        guides: [
            PianoHighlightGuide(
                id: 1,
                kind: .trigger,
                tick: 0,
                durationTicks: 480,
                practiceStepIndex: 0,
                activeNotes: [],
                triggeredNotes: [],
                releasedMIDINotes: []
            ),
        ],
        currentGuide: nil,
        measureSpans: measureSpans
    )

    #expect(layout.barlines.map(\.tick) == [0, 480, 960])
}
