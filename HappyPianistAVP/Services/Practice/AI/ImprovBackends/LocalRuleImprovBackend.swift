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

    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout: Duration
    ) async throws -> CreativeDuetResponse {
        let seed = seedResolver.resolveSeed(
            explicitSeed: generation.parameters.seed,
            sessionID: generation.sessionID
        )
        let generator = self.generator
        let promptNotes = phrase.dialogueNotes

        let replyNotes = try await runWithTimeout(timeout) {
            generator.generateRuleResponse(
                notes: promptNotes,
                params: generation.parameters,
                sessionID: generation.sessionID,
                seed: seed
            )
        }

        let schedule = scheduleBuilder.buildSchedule(from: replyNotes)
        guard schedule.isEmpty == false else {
            throw LocalRuleImprovBackendError.emptyReply
        }

        return CreativeDuetResponse(
            schedule: schedule,
            provider: kind,
            generation: generation,
            provenance: .backendGenerated(latencyMS: nil)
        )
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
