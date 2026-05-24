@preconcurrency import CoreML
import Foundation

actor CoreMLPerformanceRNNStepModel: PerformanceRNNStepModeling {
    private let model: MLModel

    init(model: MLModel) {
        self.model = model
    }

    func step(eventID: Int, temperature: Float, state: PerformanceRNNState) async throws -> PerformanceRNNStepResult {
        guard (0 ..< PerformanceRNNEventCodec.numClasses).contains(eventID) else {
            throw PerformanceRNNStepModelError.invalidEventID(expectedRange: 0 ... (PerformanceRNNEventCodec.numClasses - 1), actual: eventID)
        }

        do {
            let x = try oneHotEventInput(eventID: eventID)
            let temperatureInput = try scalarInput(value: temperature)
            let c0 = try vectorInput(values: state.c0)
            let h0 = try vectorInput(values: state.h0)
            let c1 = try vectorInput(values: state.c1)
            let h1 = try vectorInput(values: state.h1)
            let c2 = try vectorInput(values: state.c2)
            let h2 = try vectorInput(values: state.h2)

            let provider = try MLDictionaryFeatureProvider(
                dictionary: [
                    "x": MLFeatureValue(multiArray: x),
                    "temperature": MLFeatureValue(multiArray: temperatureInput),
                    "c0": MLFeatureValue(multiArray: c0),
                    "h0": MLFeatureValue(multiArray: h0),
                    "c1": MLFeatureValue(multiArray: c1),
                    "h1": MLFeatureValue(multiArray: h1),
                    "c2": MLFeatureValue(multiArray: c2),
                    "h2": MLFeatureValue(multiArray: h2),
                ]
            )

            let model = self.model
            let output = try await model.prediction(from: provider)

            let softmax = try float32Array(output, name: "softmax", expectedCount: PerformanceRNNEventCodec.numClasses)
            let nextState = try PerformanceRNNState(
                c0: float32Array(output, name: "c0_out", expectedCount: PerformanceRNNState.hiddenSize),
                h0: float32Array(output, name: "h0_out", expectedCount: PerformanceRNNState.hiddenSize),
                c1: float32Array(output, name: "c1_out", expectedCount: PerformanceRNNState.hiddenSize),
                h1: float32Array(output, name: "h1_out", expectedCount: PerformanceRNNState.hiddenSize),
                c2: float32Array(output, name: "c2_out", expectedCount: PerformanceRNNState.hiddenSize),
                h2: float32Array(output, name: "h2_out", expectedCount: PerformanceRNNState.hiddenSize)
            )
            return try PerformanceRNNStepResult(softmax: softmax, state: nextState)
        } catch let error as PerformanceRNNStepModelError {
            throw error
        } catch {
            throw PerformanceRNNStepModelError.coreMLPredictionFailed(message: String(describing: error))
        }
    }

    private func oneHotEventInput(eventID: Int) throws -> MLMultiArray {
        let multiArray = try MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: 1),
                NSNumber(value: PerformanceRNNEventCodec.numClasses),
            ],
            dataType: .float32
        )
        multiArray.resetToZeros()
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float32.self)
        ptr[eventID] = 1
        return multiArray
    }

    private func scalarInput(value: Float) throws -> MLMultiArray {
        let multiArray = try MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: 1),
            ],
            dataType: .float32
        )
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float32.self)
        ptr[0] = Float32(value)
        return multiArray
    }

    private func vectorInput(values: [Float]) throws -> MLMultiArray {
        guard values.count == PerformanceRNNState.hiddenSize else {
            throw PerformanceRNNStepModelError.invalidStateVector(
                name: "vector",
                expectedCount: PerformanceRNNState.hiddenSize,
                actualCount: values.count
            )
        }

        let multiArray = try MLMultiArray(
            shape: [
                NSNumber(value: 1),
                NSNumber(value: PerformanceRNNState.hiddenSize),
            ],
            dataType: .float32
        )
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float32.self)
        for i in 0 ..< values.count {
            ptr[i] = Float32(values[i])
        }
        return multiArray
    }

    private func float32Array(_ provider: MLFeatureProvider, name: String, expectedCount: Int) throws -> [Float] {
        guard let multiArray = provider.featureValue(for: name)?.multiArrayValue else {
            throw PerformanceRNNStepModelError.coreMLMissingOutput(name: name)
        }

        let count = multiArray.count
        guard count == expectedCount else {
            throw PerformanceRNNStepModelError.coreMLInvalidOutputShape(name: name, expectedCount: expectedCount, actualCount: count)
        }

        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float32.self)
        var values: [Float] = []
        values.reserveCapacity(count)
        for i in 0 ..< count {
            values.append(Float(ptr[i]))
        }
        return values
    }
}

private extension MLMultiArray {
    func resetToZeros() {
        let count = self.count
        switch dataType {
        case .float32:
            let ptr = dataPointer.assumingMemoryBound(to: Float32.self)
            ptr.update(repeating: 0, count: count)
        case .double:
            let ptr = dataPointer.assumingMemoryBound(to: Double.self)
            ptr.update(repeating: 0, count: count)
        default:
            for i in 0 ..< count {
                self[i] = 0
            }
        }
    }
}
