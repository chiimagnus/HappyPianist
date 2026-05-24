@testable import LonelyPianistAVP

struct FakePerformanceRNNStepModel: PerformanceRNNStepModeling {
    let softmax: [Float]
    let nextState: PerformanceRNNState

    init(softmax: [Float], nextState: PerformanceRNNState = .zeros()) {
        self.softmax = softmax
        self.nextState = nextState
    }

    func step(eventID _: Int, temperature _: Float, state _: PerformanceRNNState) async throws -> PerformanceRNNStepResult {
        try PerformanceRNNStepResult(softmax: softmax, state: nextState)
    }
}

