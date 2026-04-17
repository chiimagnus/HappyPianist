import Foundation

protocol OMRConversionServiceProtocol {
    func convert(inputURL: URL) throws -> URL
}

enum OMRConversionError: LocalizedError {
    case serverDirectoryNotFound
    case converterBinaryNotFound
    case appSupportDirectoryUnavailable
    case conversionFailed(String)
    case outputPathMissing

    var errorDescription: String? {
        switch self {
        case .serverDirectoryNotFound:
            return "OMR server directory not found. Set LONELY_PIANIST_OMR_SERVER_DIR or run from repository root."
        case .converterBinaryNotFound:
            return "OMR converter binary not found. Set LONELY_PIANIST_OMR_CONVERTER_BIN or build packaging artifact."
        case .appSupportDirectoryUnavailable:
            return "Application Support directory is unavailable."
        case .conversionFailed(let message):
            return message
        case .outputPathMissing:
            return "Conversion succeeded but output path was not found in converter output."
        }
    }
}

struct OMRConversionService: OMRConversionServiceProtocol {
    private enum ConverterCommand {
        case packagedBinary(URL)
        case pythonInterpreter(URL, serverDirectory: URL)
    }

    private let fileManager: FileManager
    private let environment: [String: String]

    init(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.fileManager = fileManager
        self.environment = environment
    }

    func convert(inputURL: URL) throws -> URL {
        let command = try resolveConverterCommand()
        let outputRoot = try resolveAppOutputRoot()

        let process = Process()
        switch command {
        case .packagedBinary(let binaryURL):
            process.executableURL = binaryURL
            process.arguments = ["--input", inputURL.path, "--output-root", outputRoot.path]
            process.currentDirectoryURL = binaryURL.deletingLastPathComponent()
        case .pythonInterpreter(let pythonPath, let serverDirectory):
            process.executableURL = pythonPath
            process.currentDirectoryURL = serverDirectory
            process.arguments = ["-m", "omr.cli", "--input", inputURL.path, "--output-root", outputRoot.path]
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw OMRConversionError.conversionFailed(output)
        }

        let outputPath = output
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("musicxml_path=") })
            .map { String($0.dropFirst("musicxml_path=".count)) }

        guard let outputPath else {
            throw OMRConversionError.outputPathMissing
        }

        return URL(fileURLWithPath: outputPath)
    }

    private func resolveConverterCommand() throws -> ConverterCommand {
        if let explicitBinary = environment["LONELY_PIANIST_OMR_CONVERTER_BIN"] {
            let binaryURL = URL(fileURLWithPath: explicitBinary)
            if fileManager.isExecutableFile(atPath: binaryURL.path) {
                return .packagedBinary(binaryURL)
            }
        }

        let bundledBinary = Bundle.main.resourceURL?.appendingPathComponent("lp-omr-convert")
        if let bundledBinary, fileManager.isExecutableFile(atPath: bundledBinary.path) {
            return .packagedBinary(bundledBinary)
        }

        let cwdBinary = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("piano_dialogue_server/omr/packaging/dist/lp-omr-convert/lp-omr-convert")
        if fileManager.isExecutableFile(atPath: cwdBinary.path) {
            return .packagedBinary(cwdBinary)
        }

        let serverDirectory = try resolveServerDirectory()
        let pythonPath = serverDirectory.appendingPathComponent(".venv/bin/python")
        if fileManager.isExecutableFile(atPath: pythonPath.path) {
            return .pythonInterpreter(pythonPath, serverDirectory: serverDirectory)
        }
        throw OMRConversionError.converterBinaryNotFound
    }

    private func resolveAppOutputRoot() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OMRConversionError.appSupportDirectoryUnavailable
        }
        let outputRoot = appSupport.appendingPathComponent("LonelyPianist/omr-jobs", isDirectory: true)
        try fileManager.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        return outputRoot
    }

    private func resolveServerDirectory() throws -> URL {
        if let explicit = environment["LONELY_PIANIST_OMR_SERVER_DIR"] {
            let url = URL(fileURLWithPath: explicit)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }

        let cwdCandidate = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("piano_dialogue_server")
        if fileManager.fileExists(atPath: cwdCandidate.path) {
            return cwdCandidate
        }

        throw OMRConversionError.serverDirectoryNotFound
    }
}
