import CoreML
@testable import LonelyPianistAVP
import Testing

struct PerformanceRNNCoreMLModelLoaderTests {
    @Test func defaultConfigurationExcludesGPU() {
        #expect(PerformanceRNNCoreMLModelLoader.defaultConfiguration().computeUnits == .cpuAndNeuralEngine)
    }

    @Test func bundledModelLoadsWithoutGPU() async throws {
        _ = try await PerformanceRNNCoreMLModelLoader().loadStepModel()
    }
}
