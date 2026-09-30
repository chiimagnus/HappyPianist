import Observation

@MainActor
@Observable
public final class GrandStaffNotationPageViewModel {
    public private(set) var plan: GrandStaffNotationPagePlan?
    var score: GrandStaffNotationScoreLayout? { plan?.score }
    public private(set) var failureMessage: String?
    private(set) var buildCount = 0
    @ObservationIgnored private var requestedInput: GrandStaffNotationScoreInput?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var worker: Task<GrandStaffNotationPagePlan, Error>?
    @ObservationIgnored private let build: @Sendable (GrandStaffNotationScoreInput) async throws -> GrandStaffNotationScoreLayout

    init(build: @escaping @Sendable (GrandStaffNotationScoreInput) async throws -> GrandStaffNotationScoreLayout) {
        self.build = build
    }

    public convenience init() { self.init(build: { try GrandStaffNotationScoreLayoutService().makeLayout(input: $0) }) }

    public func load(_ input: GrandStaffNotationScoreInput) async {
        guard !input.measureSpans.isEmpty else {
            clear()
            return
        }
        if requestedInput == input, plan != nil { return }
        generation += 1
        let requestGeneration = generation
        worker?.cancel()
        requestedInput = input
        plan = nil
        failureMessage = nil
        buildCount += 1
        let build = build
        let task = Task.detached { try GrandStaffNotationPaginationService().makePlan(score: await build(input)) }
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
            plan = result
        } catch is CancellationError {
        } catch {
            guard requestGeneration == generation else { return }
            failureMessage = "无法排版曲谱：正式曲谱来源与小节结构不一致。"
        }
    }

    public func clear() {
        generation += 1
        worker?.cancel()
        worker = nil
        requestedInput = nil
        plan = nil
        failureMessage = nil
    }
}
