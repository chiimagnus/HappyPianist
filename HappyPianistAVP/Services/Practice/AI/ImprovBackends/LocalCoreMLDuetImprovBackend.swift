import Foundation

enum LocalCoreMLDuetImprovBackendError: Error, LocalizedError, Equatable {
    case timeout
    case emptyReply

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Local CoreML duet backend timed out."
        case .emptyReply:
            "Local CoreML duet backend returned an empty reply."
        }
    }
}

actor LocalCoreMLDuetImprovBackend: ImprovBackendProtocol {
    nonisolated let kind: ImprovBackendKind = .localCoreMLDuet
    nonisolated let displayName: String = "本地 CoreML（A.I. Duet / Performance RNN）"

    private let modelLoader: any PerformanceRNNCoreMLModelLoading
    private let generator: PerformanceRNNImprovGenerator
    private let scheduleBuilder: ImprovScheduleBuilder

    init(
        modelLoader: any PerformanceRNNCoreMLModelLoading = PerformanceRNNCoreMLModelLoader(),
        generator: PerformanceRNNImprovGenerator = PerformanceRNNImprovGenerator(),
        scheduleBuilder: ImprovScheduleBuilder = ImprovScheduleBuilder()
    ) {
        self.modelLoader = modelLoader
        self.generator = generator
        self.scheduleBuilder = scheduleBuilder
    }

    func generateCreativeResponse(
        phrase: CreativeDuetPhrase,
        generation: CreativeDuetGeneration,
        timeout: Duration
    ) async throws -> CreativeDuetResponse {
        let stepModel = try await modelLoader.loadStepModel()
        let generator = self.generator
        let promptNotes = phrase.dialogueNotes

        let replyNotes = try await runWithTimeout(timeout) {
            try await generator.generateReplyNotes(
                promptNotes: promptNotes,
                params: generation.parameters,
                sessionID: generation.sessionID,
                stepModel: stepModel
            )
        }

        let schedule = scheduleBuilder.buildSchedule(from: replyNotes)
        guard schedule.isEmpty == false else {
            throw LocalCoreMLDuetImprovBackendError.emptyReply
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
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: .userInitiated) {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocalCoreMLDuetImprovBackendError.timeout
            }

            let result = try await group.next()
            group.cancelAll()

            guard let value = result else {
                throw LocalCoreMLDuetImprovBackendError.timeout
            }
            return value
        }
    }
}
