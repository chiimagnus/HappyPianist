import Foundation

enum LocalRuleImprovBackendError: Error, LocalizedError, Equatable {
    case timeout
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Local rule backend timed out."
        case .emptyReply:
            "Local rule backend returned an empty reply."
        }
    }
}

actor LocalRuleImprovBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .localRule
    nonisolated let displayName: String = "本地规则生成"

    private let generator: RuleImprovGenerator
    private let scheduleBuilder: ImprovScheduleBuilder
    private let seedResolver: ImprovSeedResolver

    init(
        generator: RuleImprovGenerator = RuleImprovGenerator(),
        scheduleBuilder: ImprovScheduleBuilder = ImprovScheduleBuilder()
    ) {
        self.generator = generator
        self.scheduleBuilder = scheduleBuilder
        seedResolver = ImprovSeedResolver()
    }

    func generatePlaybackPlan(
        request: ImprovGenerateRequestV2,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        let seed = seedResolver.resolveSeed(explicitSeed: request.params.seed, sessionID: request.sessionID)
        let generator = self.generator
        let promptNotes = request.extractDialogueNotes()

        let replyNotes = try await runWithTimeout(timeout) {
            generator.generateRuleResponse(
                notes: promptNotes,
                params: request.params,
                sessionID: request.sessionID,
                seed: seed
            )
        }

        let schedule = scheduleBuilder.buildSchedule(from: replyNotes)
        guard schedule.isEmpty == false else {
            throw LocalRuleImprovBackendError.emptyReply
        }

        return .schedule(schedule, backendLatencyMS: nil)
    }

    private func runWithTimeout<T: Sendable>(
        _ timeout: Duration,
        operation: @Sendable @escaping () throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocalRuleImprovBackendError.timeout
            }

            let result = try await group.next()
            group.cancelAll()

            guard let value = result else {
                throw LocalRuleImprovBackendError.timeout
            }
            return value
        }
    }
}
