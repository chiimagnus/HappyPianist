@testable import LonelyPianistAVP
import Testing

private actor ScriptedStepModel: PerformanceRNNStepModeling {
    private var warmupRemainingCalls: Int
    private var scriptedNextEventIDs: [Int]
    private var index = 0
    private var receivedEventIDs: [Int] = []

    init(warmupCallCount: Int, scriptedNextEventIDs: [Int]) {
        warmupRemainingCalls = warmupCallCount
        self.scriptedNextEventIDs = scriptedNextEventIDs
    }

    func step(eventID: Int, temperature _: Float, state: PerformanceRNNState) async throws -> PerformanceRNNStepResult {
        receivedEventIDs.append(eventID)
        if warmupRemainingCalls > 0 {
            warmupRemainingCalls -= 1
            let softmax = oneHot(nextEventID: 0)
            return try PerformanceRNNStepResult(softmax: softmax, state: state)
        }

        guard index < scriptedNextEventIDs.count else {
            let softmax = oneHot(nextEventID: 0)
            return try PerformanceRNNStepResult(softmax: softmax, state: state)
        }

        let next = scriptedNextEventIDs[index]
        index += 1
        let softmax = oneHot(nextEventID: next)
        return try PerformanceRNNStepResult(softmax: softmax, state: state)
    }

    func allReceivedEventIDs() -> [Int] {
        receivedEventIDs
    }

    private func oneHot(nextEventID: Int) -> [Float] {
        var softmax = Array(repeating: Float(0), count: 388)
        if (0 ..< softmax.count).contains(nextEventID) {
            softmax[nextEventID] = 1
        }
        return softmax
    }
}

@Test
func performanceRNNImprovGenerator_temperatureFromTopP_matchesPythonMapping() {
    let generator = PerformanceRNNImprovGenerator()

    #expect(abs(generator.temperatureFromTopP(0.7) - 0.8) < 0.0001)
    #expect(abs(generator.temperatureFromTopP(1.0) - 1.2) < 0.0001)
    #expect(abs(generator.temperatureFromTopP(0.95) - 1.1333333) < 0.0002)
    #expect(abs(generator.temperatureFromTopP(0.0) - 0.8) < 0.0001)
}

@Test
func performanceRNNImprovGenerator_generatesNonEmptyReplyWithScriptedModel() async throws {
    let codec = PerformanceRNNEventCodec()
    let generator = PerformanceRNNImprovGenerator(codec: codec)

    let promptNotes = [
        ImprovDialogueNote(note: 60, velocity: 80, time: 0.0, duration: 0.5),
    ]
    let promptEventIDs = codec.encode(notes: promptNotes)
    // warmup: promptEventIDs + 1 (forced VELOCITY event after warmup)
    let warmupCalls = promptEventIDs.count + 1

    // Reply script:
    // NOTE_ON 64, TIME_SHIFT 50, NOTE_OFF 64, TIME_SHIFT 100, TIME_SHIFT 50
    let stepModel = ScriptedStepModel(warmupCallCount: warmupCalls, scriptedNextEventIDs: [64, 305, 192, 355, 305])

    let params = ImprovGenerateParams(topP: 0.95, maxTokens: 128, strategy: "model", seed: 1)
    let reply = try await generator.generateReplyNotes(promptNotes: promptNotes, params: params, sessionID: "s", stepModel: stepModel)

    #expect(reply.isEmpty == false)
    #expect(reply.allSatisfy { $0.time >= 0.0 })
    #expect(reply.allSatisfy { $0.duration > 0.0 })

    // Warmup should be prompt events, followed by a forced VELOCITY event.
    let received = await stepModel.allReceivedEventIDs()
    #expect(received.count >= warmupCalls)
    let expectedVelocityEventID = 355 + PerformanceRNNEventCodec.velocityToBin(80)
    #expect(received[promptEventIDs.count] == expectedVelocityEventID)
}

@Test
func performanceRNNImprovGenerator_throwsGenerationLimitExceededWhenNoTimeShiftProgress() async {
    let codec = PerformanceRNNEventCodec()
    let generator = PerformanceRNNImprovGenerator(codec: codec)

    let promptNotes = [
        ImprovDialogueNote(note: 60, velocity: 80, time: 0.0, duration: 0.5),
    ]
    let promptEventIDs = codec.encode(notes: promptNotes)
    let warmupCalls = promptEventIDs.count + 1

    // Only emits NOTE_ON/NOTE_OFF, never TIME_SHIFT -> generator should hit safety limit.
    let repeatingEvents = Array(repeating: 60, count: 10_000)
    let stepModel = ScriptedStepModel(warmupCallCount: warmupCalls, scriptedNextEventIDs: repeatingEvents)

    let params = ImprovGenerateParams(topP: 0.95, maxTokens: 1, strategy: "model", seed: 1)
    do {
        _ = try await generator.generateReplyNotes(promptNotes: promptNotes, params: params, sessionID: "s", stepModel: stepModel)
        Issue.record("Expected generationLimitExceeded but generation finished.")
    } catch let error as PerformanceRNNImprovGeneratorError {
        #expect(error == .generationLimitExceeded)
    } catch {
        Issue.record("Unexpected error: \(String(describing: error))")
    }
}
