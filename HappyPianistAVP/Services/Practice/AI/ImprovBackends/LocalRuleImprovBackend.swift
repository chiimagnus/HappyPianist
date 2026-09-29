import Foundation

enum LocalRuleImprovBackendError: Error, LocalizedError, Equatable {
    case emptyReply

    var errorDescription: String? {
        "Local rule backend returned an empty reply."
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

    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration
    ) async throws -> CreativeDuetResponse {
        let replyNotes = generator.generateRuleResponse(
            notes: phrase.dialogueNotes,
            params: generation.parameters
        )
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
}
