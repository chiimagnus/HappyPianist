import Foundation

enum LocalCoreMLDuetImprovBackendError: Error, LocalizedError, Equatable {
    case emptyReply

    var errorDescription: String? {
        "Local CoreML duet backend returned an empty reply."
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
        generation: CreativeDuetGeneration
    ) async throws -> CreativeDuetResponse {
        let stepModel = try await modelLoader.loadStepModel()
        let replyNotes = try await generator.generateReplyNotes(
            promptNotes: phrase.dialogueNotes,
            params: generation.parameters,
            stepModel: stepModel
        )
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
}
