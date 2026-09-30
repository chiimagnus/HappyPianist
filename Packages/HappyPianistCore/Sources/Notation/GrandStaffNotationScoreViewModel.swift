import Observation

@MainActor
@Observable
final class GrandStaffNotationScoreViewModel {
    private(set) var score: GrandStaffNotationScoreLayout?
    private(set) var failureMessage: String?
    private(set) var buildCount = 0
    @ObservationIgnored private var requestedInput: GrandStaffNotationScoreInput?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var worker: Task<GrandStaffNotationScoreLayout, Error>?
    @ObservationIgnored private let build: @Sendable (GrandStaffNotationScoreInput) async throws -> GrandStaffNotationScoreLayout

    init(build: @escaping @Sendable (GrandStaffNotationScoreInput) async throws -> GrandStaffNotationScoreLayout = {
        try GrandStaffNotationScoreLayoutService().makeLayout(input: $0)
    }) {
        self.build = build
    }

    func load(_ input: GrandStaffNotationScoreInput) async {
        guard !input.projection.performedOccurrences.isEmpty else {
            clear()
            return
        }
        if requestedInput == input, score != nil { return }
        generation += 1
        let requestGeneration = generation
        worker?.cancel()
        requestedInput = input
        score = nil
        failureMessage = nil
        buildCount += 1
        let build = build
        let task = Task.detached { try await build(input) }
        worker = task
        defer {
            if requestGeneration == generation { worker = nil }
        }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            score = result
        } catch is CancellationError {
        } catch {
            guard requestGeneration == generation else { return }
            failureMessage = "无法排版曲谱：正式曲谱来源与小节结构不一致。"
        }
    }

    func clear() {
        generation += 1
        worker?.cancel()
        worker = nil
        requestedInput = nil
        score = nil
        failureMessage = nil
    }
}
