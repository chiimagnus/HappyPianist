import Foundation

struct PerformanceRNNState: Equatable, Sendable {
    static let hiddenSize = 512

    var c0: [Float]
    var h0: [Float]
    var c1: [Float]
    var h1: [Float]
    var c2: [Float]
    var h2: [Float]

    init(c0: [Float], h0: [Float], c1: [Float], h1: [Float], c2: [Float], h2: [Float]) throws {
        func validate(_ name: String, _ values: [Float]) throws -> [Float] {
            guard values.count == Self.hiddenSize else {
                throw PerformanceRNNStepModelError.invalidStateVector(name: name, expectedCount: Self.hiddenSize, actualCount: values.count)
            }
            return values
        }

        self.c0 = try validate("c0", c0)
        self.h0 = try validate("h0", h0)
        self.c1 = try validate("c1", c1)
        self.h1 = try validate("h1", h1)
        self.c2 = try validate("c2", c2)
        self.h2 = try validate("h2", h2)
    }

    static func zeros() -> PerformanceRNNState {
        let zeros = Array(repeating: Float.zero, count: hiddenSize)
        return PerformanceRNNState(uncheckedC0: zeros, uncheckedH0: zeros, uncheckedC1: zeros, uncheckedH1: zeros, uncheckedC2: zeros, uncheckedH2: zeros)
    }

    private init(
        uncheckedC0: [Float],
        uncheckedH0: [Float],
        uncheckedC1: [Float],
        uncheckedH1: [Float],
        uncheckedC2: [Float],
        uncheckedH2: [Float]
    ) {
        c0 = uncheckedC0
        h0 = uncheckedH0
        c1 = uncheckedC1
        h1 = uncheckedH1
        c2 = uncheckedC2
        h2 = uncheckedH2
    }
}

struct PerformanceRNNStepResult: Equatable, Sendable {
    static let numClasses = PerformanceRNNEventCodec.numClasses

    var softmax: [Float]
    var state: PerformanceRNNState

    init(softmax: [Float], state: PerformanceRNNState) throws {
        guard softmax.count == Self.numClasses else {
            throw PerformanceRNNStepModelError.invalidSoftmax(expectedCount: Self.numClasses, actualCount: softmax.count)
        }
        self.softmax = softmax
        self.state = state
    }
}

enum PerformanceRNNStepModelError: Error, LocalizedError, Equatable, Sendable {
    case invalidEventID(expectedRange: ClosedRange<Int>, actual: Int)
    case invalidSoftmax(expectedCount: Int, actualCount: Int)
    case invalidStateVector(name: String, expectedCount: Int, actualCount: Int)
    case coreMLPredictionFailed(message: String)
    case coreMLMissingOutput(name: String)
    case coreMLInvalidOutputShape(name: String, expectedCount: Int, actualCount: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidEventID(expectedRange, actual):
            "Invalid eventID=\(actual), expected in \(expectedRange)."
        case let .invalidSoftmax(expectedCount, actualCount):
            "Invalid softmax length=\(actualCount), expected \(expectedCount)."
        case let .invalidStateVector(name, expectedCount, actualCount):
            "Invalid state vector '\(name)' length=\(actualCount), expected \(expectedCount)."
        case let .coreMLPredictionFailed(message):
            "CoreML prediction failed: \(message)"
        case let .coreMLMissingOutput(name):
            "CoreML output '\(name)' is missing."
        case let .coreMLInvalidOutputShape(name, expectedCount, actualCount):
            "CoreML output '\(name)' has \(actualCount) values, expected \(expectedCount)."
        }
    }
}

protocol PerformanceRNNStepModeling: Sendable {
    func step(eventID: Int, temperature: Float, state: PerformanceRNNState) async throws -> PerformanceRNNStepResult
}
