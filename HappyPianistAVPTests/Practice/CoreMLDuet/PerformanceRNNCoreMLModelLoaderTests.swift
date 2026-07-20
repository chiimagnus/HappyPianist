import Foundation
import CoreML
@testable import HappyPianistAVP
import Testing

private let hasBundledPerformanceRNNModel =
    Bundle.main.url(forResource: "AIDuetPerformanceRNN", withExtension: "mlmodelc") != nil
    || Bundle.main.url(forResource: "AIDuetPerformanceRNN", withExtension: "mlpackage") != nil

struct PerformanceRNNCoreMLModelLoaderTests {
    @Test func defaultConfigurationExcludesGPU() {
        #expect(PerformanceRNNCoreMLModelLoader.defaultConfiguration().computeUnits == .cpuAndNeuralEngine)
    }

    @Test(.enabled(
        if: hasBundledPerformanceRNNModel,
        "The private Core ML model is not bundled in this checkout."
    ))
    func bundledModelLoadsWithoutGPU() async throws {
        _ = try await PerformanceRNNCoreMLModelLoader().loadStepModel()
    }
}
