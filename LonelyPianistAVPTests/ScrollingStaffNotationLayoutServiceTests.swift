import Foundation
import simd
@testable import LonelyPianistAVP
import Testing

@Test
func notationLayoutPlacesCurrentGuideAtPlaybackLine() {
    let guides = [
        makeNotationGuide(id: 1, tick: 0, midiNotes: [60]),
        makeNotationGuide(id: 2, tick: 480, midiNotes: [64, 67]),
        makeNotationGuide(id: 3, tick: 960, midiNotes: [72]),
    ]

    let items = ScrollingStaffNotationLayoutService().makeItems(
        guides: guides,
        currentGuide: guides[1],
        halfWindowTicks: 960
    )

    let c4 = items.first { $0.midiNote == 60 }
    let e4 = items.first { $0.midiNote == 64 }
    let g4 = items.first { $0.midiNote == 67 }
    let c5 = items.first { $0.midiNote == 72 }

    #expect(c4?.xPosition == 0.25)
    #expect(e4?.xPosition == 0.5)
    #expect(g4?.xPosition == 0.5)
    #expect(c5?.xPosition == 0.75)
    #expect(e4?.isHighlighted == true)
    #expect(g4?.isHighlighted == true)
    #expect(c4?.isHighlighted == false)
    #expect(c5?.isHighlighted == false)
}

@Test
func notationLayoutMapsMIDINotesToTrebleStaffSteps() {
    let guide = makeNotationGuide(id: 1, tick: 0, midiNotes: [60, 64, 67, 72])

    let items = ScrollingStaffNotationLayoutService().makeItems(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    )

    #expect(items.first { $0.midiNote == 60 }?.staffStep == -2)
    #expect(items.first { $0.midiNote == 64 }?.staffStep == 0)
    #expect(items.first { $0.midiNote == 67 }?.staffStep == 2)
    #expect(items.first { $0.midiNote == 72 }?.staffStep == 5)
}

@Test
func notationLayoutMapsBassStaffNotesToBassStaffSteps() {
    let guide = makeNotationGuide(id: 1, tick: 0, midiNotes: [43, 48, 57], staff: 2)

    let items = ScrollingStaffNotationLayoutService().makeItems(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    )

    #expect(items.first { $0.midiNote == 43 }?.staffStep == 0)
    #expect(items.first { $0.midiNote == 48 }?.staffStep == 3)
    #expect(items.first { $0.midiNote == 57 }?.staffStep == 8)
}

@Test
func notationLayoutMarksAccidentalsForBlackKeys() {
    let guide = makeNotationGuide(id: 1, tick: 0, midiNotes: [61, 63, 66])

    let items = ScrollingStaffNotationLayoutService().makeItems(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    )

    #expect(items.allSatisfy { $0.showsSharpAccidental })
}

@Test
func notationLayoutPreservesEngravingMetadataFromGuideNotes() {
    let note = PianoHighlightNote(
        occurrenceID: "notation-rich-c4",
        midiNote: 60,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 120,
        offTick: 600,
        fingeringText: "3",
        isGrace: true,
        tieStart: true,
        tieStop: false,
        articulations: [.staccato, .accent],
        arpeggiate: MusicXMLArpeggiate(numberToken: "1", directionToken: "up")
    )
    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 120,
        durationTicks: 480,
        practiceStepIndex: 0,
        activeNotes: [note],
        triggeredNotes: [note],
        releasedMIDINotes: []
    )

    let item = ScrollingStaffNotationLayoutService().makeItems(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    ).first

    #expect(item?.durationTicks == 480)
    #expect(item?.fingeringText == "3")
    #expect(item?.isGrace == true)
    #expect(item?.tieStart == true)
    #expect(item?.tieStop == false)
    #expect(item?.articulations == [.staccato, .accent])
    #expect(item?.arpeggiate == MusicXMLArpeggiate(numberToken: "1", directionToken: "up"))
}

@Test
func notationLayoutDoesNotExposeDanglingTieWithoutVisibleContinuation() {
    let tiedStart = PianoHighlightNote(
        occurrenceID: "tie-start-c4",
        midiNote: 60,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 0,
        offTick: 960,
        fingeringText: nil,
        tieStart: true
    )
    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        durationTicks: 960,
        practiceStepIndex: 0,
        activeNotes: [tiedStart],
        triggeredNotes: [tiedStart],
        releasedMIDINotes: []
    )

    let item = ScrollingStaffNotationLayoutService().makeItems(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    ).first

    #expect(item?.tieEndXPosition == nil)
}

@Test
func notationLayoutGroupsSameTickNotesIntoChordAndOffsetsAdjacentNoteheads() {
    let guide = makeNotationGuide(id: 1, tick: 0, midiNotes: [64, 65])

    let layout = ScrollingStaffNotationLayoutService().makeLayout(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    )

    #expect(layout.chords.count == 1)
    #expect(layout.chords.first?.itemIDs.count == 2)
    #expect(layout.items.allSatisfy { $0.chordID == layout.chords.first?.id })
    #expect(layout.items.contains { abs($0.noteHeadXOffset) > 0 })
}

@Test
func notationLayoutCreatesRestForVisibleGapGuide() {
    let guide = PianoHighlightGuide(
        id: 1,
        kind: .gap,
        tick: 480,
        durationTicks: 480,
        practiceStepIndex: nil,
        activeNotes: [],
        triggeredNotes: [],
        releasedMIDINotes: []
    )

    let layout = ScrollingStaffNotationLayoutService().makeLayout(
        guides: [guide],
        currentGuide: guide,
        halfWindowTicks: 960
    )

    #expect(layout.rests.count == 1)
    #expect(layout.rests.first?.xPosition == 0.5)
    #expect(layout.rests.first?.noteValue == .quarter)
}

@Test
func notationLayoutCreatesBarlinesFromMeasureSpans() {
    let guide = makeNotationGuide(id: 1, tick: 480, midiNotes: [64])
    let measures = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 480),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, startTick: 480, endTick: 960),
    ]

    let layout = ScrollingStaffNotationLayoutService().makeLayout(
        guides: [guide],
        currentGuide: guide,
        measureSpans: measures,
        halfWindowTicks: 960
    )

    #expect(layout.barlines.contains { $0.tick == 480 && $0.xPosition == 0.5 })
}

@Test
func notationLayoutBeamsConsecutiveEighthNoteChords() {
    let guides = [
        makeNotationGuide(id: 1, tick: 0, midiNotes: [64], durationTicks: 240),
        makeNotationGuide(id: 2, tick: 240, midiNotes: [65], durationTicks: 240),
        makeNotationGuide(id: 3, tick: 480, midiNotes: [67], durationTicks: 480),
    ]

    let layout = ScrollingStaffNotationLayoutService().makeLayout(
        guides: guides,
        currentGuide: guides[0],
        halfWindowTicks: 960
    )

    #expect(layout.beams.count == 1)
    #expect(layout.beams.first?.chordIDs.count == 2)
    #expect(layout.items.filter { $0.noteValue == .eighth }.allSatisfy { $0.beamID == layout.beams.first?.id })
    #expect(layout.items.first { $0.midiNote == 67 }?.beamID == nil)
}

@Test
func notationLayoutOnlyDrawsLedgerLineWhereNoteHeadSits() {
    let service = ScrollingStaffNotationLayoutService()

    #expect(service.ledgerStaffSteps(for: -2) == [-2])
    #expect(service.ledgerStaffSteps(for: -4) == [-4])
    #expect(service.ledgerStaffSteps(for: -3) == [])
    #expect(service.ledgerStaffSteps(for: 10) == [10])
    #expect(service.ledgerStaffSteps(for: 11) == [])
}

@Test
@MainActor
func practiceSessionExposesNotationMeasureSpansAndContextForCurrentGuide() {
    let note = PianoHighlightNote(
        occurrenceID: "context-note",
        midiNote: 64,
        staff: 1,
        voice: 1,
        velocity: 96,
        onTick: 960,
        offTick: 1_440,
        fingeringText: nil
    )
    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 960,
        durationTicks: 480,
        practiceStepIndex: 0,
        activeNotes: [note],
        triggeredNotes: [note],
        releasedMIDINotes: []
    )
    let measureSpans = [
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 1, startTick: 0, endTick: 960),
        MusicXMLMeasureSpan(partID: "P1", measureNumber: 2, startTick: 960, endTick: 1_920),
    ]
    let scope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    let attributeTimeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: [
            MusicXMLTimeSignatureEvent(tick: 0, beats: 3, beatType: 4, scope: scope),
        ],
        keySignatureEvents: [
            MusicXMLKeySignatureEvent(tick: 0, fifths: -2, modeToken: nil, scope: scope),
        ],
        clefEvents: [
            MusicXMLClefEvent(tick: 0, signToken: "G", line: 2, octaveChange: nil, numberToken: "1", scope: scope),
        ]
    )
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NotationNoopPressDetectionService(),
        chordAttemptAccumulator: NotationNoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [PracticeStep(tick: 960, notes: [PracticeStepNote(midiNote: 64, staff: 1)])],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        attributeTimeline: attributeTimeline,
        highlightGuides: [guide],
        measureSpans: measureSpans
    )
    viewModel.startGuidingIfReady()

    #expect(viewModel.notationMeasureSpans == measureSpans)
    #expect(viewModel.currentNotationContext == ScrollingStaffNotationContext(
        clefSymbol: "𝄞",
        keySignatureText: "♭♭",
        keySignatureFifths: -2,
        timeSignatureText: "3/4"
    ))
}

@Test
@MainActor
func practiceSessionUsesCurrentGuideStaffForNotationClefContext() {
    let note = PianoHighlightNote(
        occurrenceID: "bass-context-note",
        midiNote: 48,
        staff: 2,
        voice: 1,
        velocity: 96,
        onTick: 0,
        offTick: 480,
        fingeringText: nil
    )
    let guide = PianoHighlightGuide(
        id: 1,
        kind: .trigger,
        tick: 0,
        durationTicks: 480,
        practiceStepIndex: 0,
        activeNotes: [note],
        triggeredNotes: [note],
        releasedMIDINotes: []
    )
    let scope = MusicXMLEventScope(partID: "P1", staff: nil, voice: nil)
    let attributeTimeline = MusicXMLAttributeTimeline(
        timeSignatureEvents: [],
        keySignatureEvents: [],
        clefEvents: [
            MusicXMLClefEvent(tick: 0, signToken: "G", line: 2, octaveChange: nil, numberToken: "1", scope: scope),
            MusicXMLClefEvent(tick: 0, signToken: "F", line: 4, octaveChange: nil, numberToken: "2", scope: scope),
        ]
    )
    let viewModel = PracticeSessionViewModel(
        pressDetectionService: NotationNoopPressDetectionService(),
        chordAttemptAccumulator: NotationNoopChordAttemptAccumulator(),
        sleeper: TaskSleeper()
    )

    viewModel.setSteps(
        [PracticeStep(tick: 0, notes: [PracticeStepNote(midiNote: 48, staff: 2)])],
        tempoMap: MusicXMLTempoMap(tempoEvents: []),
        attributeTimeline: attributeTimeline,
        highlightGuides: [guide],
        measureSpans: []
    )
    viewModel.startGuidingIfReady()

    #expect(viewModel.currentNotationContext?.clefSymbol == "𝄢")
}

private func makeNotationGuide(
    id: Int,
    tick: Int,
    midiNotes: [Int],
    durationTicks: Int = 480,
    staff: Int = 1
) -> PianoHighlightGuide {
    let notes = midiNotes.enumerated().map { index, midiNote in
        PianoHighlightNote(
            occurrenceID: "notation-\(id)-\(index)-\(midiNote)",
            midiNote: midiNote,
            staff: staff,
            voice: 1,
            velocity: 96,
            onTick: tick,
            offTick: tick + durationTicks,
            fingeringText: nil
        )
    }

    return PianoHighlightGuide(
        id: id,
        kind: .trigger,
        tick: tick,
        durationTicks: durationTicks,
        practiceStepIndex: id - 1,
        activeNotes: notes,
        triggeredNotes: notes,
        releasedMIDINotes: []
    )
}

private struct NotationNoopPressDetectionService: PressDetectionServiceProtocol {
    func detectPressedNotes(
        fingerTips _: [String: SIMD3<Float>],
        keyboardGeometry _: PianoKeyboardGeometry?,
        at _: Date
    ) -> Set<Int> {
        []
    }
}

private final class NotationNoopChordAttemptAccumulator: ChordAttemptAccumulatorProtocol {
    func register(pressedNotes _: Set<Int>, expectedNotes _: [Int], tolerance _: Int, at _: Date) -> Bool {
        false
    }

    func reset() {}
}
