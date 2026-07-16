@preconcurrency import CoreML
import Foundation

enum PerformanceRNNCoreMLModelLoaderError: Error, LocalizedError, Equatable {
    case modelMissing(expectedNames: [String])
    case compileFailed(modelName: String, message: String)
    case loadFailed(modelName: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .modelMissing(expectedNames):
            "CoreML model is missing. Expected one of: \(expectedNames.joined(separator: ", "))."
        case let .compileFailed(modelName, message):
            "CoreML compile failed (\(modelName)): \(message)"
        case let .loadFailed(modelName, message):
            "CoreML load failed (\(modelName)): \(message)"
        }
    }

    static func sanitizeMessage(_ message: String) -> String {
        var sanitized = message
        let home = NSHomeDirectory()
        if home.isEmpty == false {
            sanitized = sanitized.replacing(home, with: "~")
        }
        sanitized = sanitized.replacing("file://", with: "")
        return sanitized
    }
}

protocol PerformanceRNNCoreMLModelLoading: Sendable {
    func loadStepModel() async throws -> any PerformanceRNNStepModeling
}

actor PerformanceRNNCoreMLModelLoader: PerformanceRNNCoreMLModelLoading {
    private static let modelBaseName = "AIDuetPerformanceRNN"
    private static let compiledExtension = "mlmodelc"
    private static let packageExtension = "mlpackage"

    private let bundle: Bundle
    private let fileManager: FileManager
    private let configuration: MLModelConfiguration

    private var cachedStepModel: CoreMLPerformanceRNNStepModel?

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        configuration: MLModelConfiguration = PerformanceRNNCoreMLModelLoader.defaultConfiguration()
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.configuration = configuration
    }

    static func defaultConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        return configuration
    }

    func loadStepModel() async throws -> any PerformanceRNNStepModeling {
        if let cachedStepModel {
            return cachedStepModel
        }

        let modelURL = try resolveCompiledModelURL()
        do {
            let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
            let stepModel = CoreMLPerformanceRNNStepModel(model: model)
            cachedStepModel = stepModel
            return stepModel
        } catch {
            throw PerformanceRNNCoreMLModelLoaderError.loadFailed(
                modelName: "\(Self.modelBaseName).\(Self.compiledExtension)",
                message: PerformanceRNNCoreMLModelLoaderError.sanitizeMessage(String(describing: error))
            )
        }
    }

    private func resolveCompiledModelURL() throws -> URL {
        if let compiledInBundle = bundle.url(forResource: Self.modelBaseName, withExtension: Self.compiledExtension) {
            return compiledInBundle
        }

        guard let packageInBundle = bundle.url(forResource: Self.modelBaseName, withExtension: Self.packageExtension) else {
            throw PerformanceRNNCoreMLModelLoaderError.modelMissing(
                expectedNames: [
                    "\(Self.modelBaseName).\(Self.compiledExtension)",
                    "\(Self.modelBaseName).\(Self.packageExtension)",
                ]
            )
        }

        do {
            let compiledURL = try MLModel.compileModel(at: packageInBundle)
            return bestEffortCacheCompiledModel(compiledURL: compiledURL) ?? compiledURL
        } catch {
            throw PerformanceRNNCoreMLModelLoaderError.compileFailed(
                modelName: "\(Self.modelBaseName).\(Self.packageExtension)",
                message: PerformanceRNNCoreMLModelLoaderError.sanitizeMessage(String(describing: error))
            )
        }
    }

    private func bestEffortCacheCompiledModel(compiledURL: URL) -> URL? {
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let cacheURL = cachesDirectory.appending(path: "\(Self.modelBaseName).\(Self.compiledExtension)")

        do {
            if fileManager.fileExists(atPath: cacheURL.path()) {
                try fileManager.removeItem(at: cacheURL)
            }
            try fileManager.copyItem(at: compiledURL, to: cacheURL)
            return cacheURL
        } catch {
            return nil
        }
    }
}
