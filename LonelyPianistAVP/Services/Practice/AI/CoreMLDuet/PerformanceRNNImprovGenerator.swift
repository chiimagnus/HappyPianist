import Foundation
import ImprovEngines
import ImprovProtocol

enum PerformanceRNNImprovGeneratorError: Error, LocalizedError, Equatable, Sendable {
    case emptyPrompt
    case invalidDistribution
    case generationLimitExceeded

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            "Prompt is empty."
        case .invalidDistribution:
            "Model returned an invalid probability distribution."
        case .generationLimitExceeded:
            "Generation limit exceeded."
        }
    }
}

struct PerformanceRNNImprovGenerator: Sendable {
    private let codec: PerformanceRNNEventCodec
    private let seedResolver: ImprovSeedResolver

    init(codec: PerformanceRNNEventCodec = PerformanceRNNEventCodec(), seedResolver: ImprovSeedResolver = ImprovSeedResolver()) {
        self.codec = codec
        self.seedResolver = seedResolver
    }

    func temperatureFromTopP(_ topP: Double) -> Float {
        let p = max(0.0, min(1.0, topP))
        let t: Double
        if p <= 0.7 {
            t = 0.0
        } else if p >= 1.0 {
            t = 1.0
        } else {
            t = (p - 0.7) / 0.3
        }
        let temperature = 0.8 + (1.2 - 0.8) * t
        return Float(max(0.5, min(1.5, temperature)))
    }

    func replyLenSecondsFromMaxTokens(_ maxTokens: Int) -> Double {
        let seconds = Double(max(0, maxTokens)) / 64.0
        return max(2.0, min(12.0, seconds))
    }

    func generateReplyNotes<StepModel: PerformanceRNNStepModeling>(
        promptNotes: [ImprovDialogueNote],
        params: ImprovGenerateParams,
        sessionID: String?,
        stepModel: StepModel
    ) async throws -> [ImprovDialogueNote] {
        guard promptNotes.isEmpty == false else {
            throw PerformanceRNNImprovGeneratorError.emptyPrompt
        }

        let temperature = temperatureFromTopP(params.topP)
        let promptEndTimeSeconds = promptNotes.map { $0.time + $0.duration }.max() ?? 0.0
        let promptEndStep = Int(promptEndTimeSeconds * 100.0 + 0.5)

        let replyLenSec = replyLenSecondsFromMaxTokens(params.maxTokens)
        let targetEndStep = promptEndStep + Int(replyLenSec * 100.0 + 0.5)

        let seed = seedResolver.resolveSeed(explicitSeed: params.seed, sessionID: sessionID)
        var rng = PythonRandom(seed: seed)

        var eventStream = codec.encode(notes: promptNotes)
        var state = PerformanceRNNState.zeros()
        var currentStep = 0

        for eventID in eventStream {
            try Task.checkCancellation()
            let stepResult = try await stepModel.step(eventID: eventID, temperature: temperature, state: state)
            state = stepResult.state
            if (256 ... 355).contains(eventID) {
                currentStep += (eventID - 255)
            }
        }

        // Ensure reply begins with an explicit VELOCITY event, so decoder doesn't rely on a default.
        let defaultVelocity: Int = {
            let velocities = promptNotes.map(\.velocity).filter { $0 > 0 }
            if velocities.isEmpty { return 80 }
            return max(1, min(127, Int(Double(velocities.reduce(0, +)) / Double(velocities.count))))
        }()
        let velocityBin = PerformanceRNNEventCodec.velocityToBin(defaultVelocity)
        let velocityEventID = 355 + velocityBin
        if eventStream.last != velocityEventID {
            try Task.checkCancellation()
            let stepResult = try await stepModel.step(eventID: velocityEventID, temperature: temperature, state: state)
            state = stepResult.state
            eventStream.append(velocityEventID)
        }

        guard let initialLastEventID = eventStream.last else {
            throw PerformanceRNNImprovGeneratorError.emptyPrompt
        }
        var lastEventID = initialLastEventID
        let maxGeneratedEvents = max(2048, params.maxTokens * 32)
        var generatedCount = 0

        while currentStep < targetEndStep {
            try Task.checkCancellation()
            if generatedCount >= maxGeneratedEvents {
                throw PerformanceRNNImprovGeneratorError.generationLimitExceeded
            }

            let stepResult = try await stepModel.step(eventID: lastEventID, temperature: temperature, state: state)
            state = stepResult.state

            let nextEventID = try sampleEventID(probabilities: stepResult.softmax, rng: &rng)
            eventStream.append(nextEventID)
            generatedCount += 1
            lastEventID = nextEventID

            if (256 ... 355).contains(nextEventID) {
                currentStep += (nextEventID - 255)
            }
        }

        return codec.decode(eventIDs: eventStream, promptEndTimeSeconds: promptEndTimeSeconds)
    }

    private func sampleEventID(probabilities: [Float], rng: inout PythonRandom) throws -> Int {
        guard probabilities.count == PerformanceRNNEventCodec.numClasses else {
            throw PerformanceRNNImprovGeneratorError.invalidDistribution
        }

        var sum = 0.0
        for p in probabilities {
            if p.isFinite == false { continue }
            if p > 0 { sum += Double(p) }
        }
        guard sum > 0 else {
            throw PerformanceRNNImprovGeneratorError.invalidDistribution
        }

        let r = rng.random() * sum
        var cumulative = 0.0
        for i in 0 ..< probabilities.count {
            let p = Double(probabilities[i])
            if p.isFinite == false || p <= 0 { continue }
            cumulative += p
            if r <= cumulative {
                return i
            }
        }

        // Fallback (numeric edge).
        return probabilities.count - 1
    }
}
