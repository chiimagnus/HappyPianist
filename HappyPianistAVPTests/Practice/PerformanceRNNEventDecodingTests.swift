@testable import HappyPianistAVP
import Testing

private struct FixedPerformanceRNNModelLoader: PerformanceRNNCoreMLModelLoading {
    let stepModel: any PerformanceRNNStepModeling

    func loadStepModel() async throws -> any PerformanceRNNStepModeling {
        stepModel
    }
}

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
func localCoreMLDuetBackendQualityCorpusUsesNativeCreativeResponse() async throws {
    let corpus = DuetQualityRegressionFixtures.coreMLQualityCorpus
    #expect(corpus.provider == .localCoreMLDuet)
    #expect(corpus.parameters.seed == .some(corpus.seed))
    #expect(corpus.parameters.strategy == "model")
    guard case let .scriptedCoreML(eventIDs) = corpus.response else {
        Issue.record("Core ML corpus must use its scripted step-model sequence.")
        return
    }

    let codec = PerformanceRNNEventCodec()
    let warmupCalls = codec.encode(notes: corpus.promptNotes).count + 1
    let backend = LocalCoreMLDuetImprovBackend(
        modelLoader: FixedPerformanceRNNModelLoader(
            stepModel: ScriptedStepModel(
                warmupCallCount: warmupCalls,
                scriptedNextEventIDs: eventIDs
            )
        ),
        generator: PerformanceRNNImprovGenerator(codec: codec),
        scheduleBuilder: ImprovScheduleBuilder()
    )
    let generation = corpus.creativeGeneration
    let response = try await backend.generateCreativeResponse(
        phrase: corpus.creativePhrase,
        generation: generation,
        timeout: .seconds(1)
    )

    #expect(response.provider == corpus.provider)
    #expect(response.generation == generation)
    #expect(response.provenance == .backendGenerated(latencyMS: nil))
    #expect(response.schedule.isEmpty == false)
    #expect(ImprovQualityRubric().assess(response.schedule).band == corpus.expectedBand)
}
