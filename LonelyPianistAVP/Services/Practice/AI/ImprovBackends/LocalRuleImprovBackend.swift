import CryptoKit
import Foundation
import ImprovEngines
import ImprovProtocol

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

    init(
        generator: RuleImprovGenerator = RuleImprovGenerator(),
        scheduleBuilder: ImprovScheduleBuilder = ImprovScheduleBuilder()
    ) {
        self.generator = generator
        self.scheduleBuilder = scheduleBuilder
    }

    func generatePlaybackPlan(
        request: ImprovGenerateRequest,
        timeout: Duration
    ) async throws -> ImprovBackendPlaybackPlan {
        let seed = resolveSeed(for: request)
        let generator = self.generator

        let replyNotes = try await runWithTimeout(timeout) {
            generator.generateRuleResponse(
                notes: request.notes,
                params: request.params,
                sessionID: request.sessionID,
                seed: seed
            )
        }

        let schedule = scheduleBuilder.buildSchedule(from: replyNotes)
        guard schedule.isEmpty == false else {
            throw LocalRuleImprovBackendError.emptyReply
        }

        return .schedule(schedule)
    }

    private nonisolated func resolveSeed(for request: ImprovGenerateRequest) -> UInt64 {
        if let seed = request.params.seed {
            return seed
        }
        if let sessionID = request.sessionID {
            return deriveSeed(fromSessionID: sessionID)
        }
        return 0
    }

    private nonisolated func deriveSeed(fromSessionID sessionID: String) -> UInt64 {
        let digest = SHA256.hash(data: Data(sessionID.utf8))
        let bytes = Array(digest)
        var seed: UInt64 = 0
        for i in 0 ..< min(8, bytes.count) {
            seed = (seed << 8) | UInt64(bytes[i])
        }
        return seed
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
