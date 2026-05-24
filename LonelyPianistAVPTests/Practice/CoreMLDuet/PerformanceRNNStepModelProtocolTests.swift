@testable import LonelyPianistAVP
import Testing

@Test
func performanceRNNState_zerosHasExpectedShape() {
    let state = PerformanceRNNState.zeros()
    #expect(state.c0.count == 512)
    #expect(state.h0.count == 512)
    #expect(state.c1.count == 512)
    #expect(state.h1.count == 512)
    #expect(state.c2.count == 512)
    #expect(state.h2.count == 512)
}

@Test
func performanceRNNStepResult_enforcesSoftmaxLength() {
    let state = PerformanceRNNState.zeros()
    #expect(throws: PerformanceRNNStepModelError.invalidSoftmax(expectedCount: 388, actualCount: 0)) {
        _ = try PerformanceRNNStepResult(softmax: [], state: state)
    }
}

@Test
func fakePerformanceRNNStepModel_returnsExpectedShapes() async throws {
    let state = PerformanceRNNState.zeros()
    let softmax = Array(repeating: Float(0), count: 388)
    let model = FakePerformanceRNNStepModel(softmax: softmax, nextState: state)

    let result = try await model.step(eventID: 0, temperature: 1.0, state: state)
    #expect(result.softmax.count == 388)
    #expect(result.state.c0.count == 512)
}

