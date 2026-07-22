@testable import HappyPianistAVP
import Testing

@Test
func performanceRNNEventCodec_decodesSingleNoteWithVelocity() {
    let codec = PerformanceRNNEventCodec()
    let notes = codec.decode(eventIDs: [375, 60, 305, 188], promptEndTimeSeconds: 0.0)

    #expect(notes.count == 1)
    #expect(notes[0].note == 60)
    #expect(notes[0].velocity == 77)
    #expect(notes[0].time == 0.0)
    #expect(abs(notes[0].duration - 0.5) < 0.0001)
}

@Test
func performanceRNNEventCodec_clipsNotesAcrossPromptEnd() {
    let codec = PerformanceRNNEventCodec()
    let notes = codec.decode(eventIDs: [375, 60, 305, 188], promptEndTimeSeconds: 0.25)

    #expect(notes.count == 1)
    #expect(notes[0].time == 0.0)
    #expect(abs(notes[0].duration - 0.25) < 0.0001)
}

@Test
func performanceRNNEventCodec_decodesChordInStableOrder() {
    let codec = PerformanceRNNEventCodec()
    let notes = codec.decode(eventIDs: [375, 60, 64, 67, 330, 188, 192, 195], promptEndTimeSeconds: 0.0)

    #expect(notes.count == 3)
    #expect(notes[0].note == 60)
    #expect(notes[1].note == 64)
    #expect(notes[2].note == 67)
    #expect(notes.allSatisfy { $0.time >= 0.0 })
    #expect(notes.allSatisfy { $0.duration > 0.0 })
}

@Test
func performanceRNNEventCodecCoreMLQualityCorpusUsesTheSharedGate() {
    let corpus = DuetQualityRegressionFixtures.coreMLQualityCorpus
    #expect(corpus.provider == .localCoreMLDuet)
    #expect(corpus.parameters.seed == .some(corpus.seed))
    #expect(corpus.parameters.strategy == "model")
    guard case let .coreMLEventIDs(eventIDs) = corpus.response else {
        Issue.record("Core ML corpus must decode its golden event IDs.")
        return
    }

    let notes = PerformanceRNNEventCodec().decode(eventIDs: eventIDs, promptEndTimeSeconds: 0)
    let schedule = ImprovScheduleBuilder().buildSchedule(from: notes, leadInSeconds: 0)

    #expect(schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(schedule).band == corpus.expectedBand)
}
