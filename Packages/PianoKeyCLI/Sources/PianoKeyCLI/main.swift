import AVFoundation
import AudioToolbox
import Foundation

enum CLIExitCode: Int32 {
    case success = 0
    case invalidArguments = 64
    case runtimeFailure = 1
}

enum CLIError: LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingOptionValue(String)
    case missingRequiredOption(String)
    case invalidNumber(option: String, value: String)
    case inputFileNotFound(String)
    case outputPathInvalid(String)
    case soundBankNotFound
    case engineFailure(String)

    var exitCode: CLIExitCode {
        switch self {
        case .missingCommand, .unknownCommand, .missingOptionValue, .missingRequiredOption, .invalidNumber:
            return .invalidArguments
        case .inputFileNotFound, .outputPathInvalid, .soundBankNotFound, .engineFailure:
            return .runtimeFailure
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "No command provided. Use 'pianokey-cli help'."
        case .unknownCommand(let command):
            return "Unknown command '\(command)'. Use 'pianokey-cli help'."
        case .missingOptionValue(let option):
            return "Missing value for option '\(option)'."
        case .missingRequiredOption(let option):
            return "Missing required option '\(option)'."
        case .invalidNumber(let option, let value):
            return "Invalid numeric value '\(value)' for option '\(option)'."
        case .inputFileNotFound(let path):
            return "Input MIDI file does not exist: \(path)"
        case .outputPathInvalid(let path):
            return "Output path is invalid: \(path)"
        case .soundBankNotFound:
            return "No built-in piano sound bank found. Provide --sound-bank <path>."
        case .engineFailure(let message):
            return "Audio rendering failed: \(message)"
        }
    }
}

struct RenderOptions {
    let inputPath: String
    let outputPath: String
    let tailSeconds: Double
    let sampleRate: Double
    let soundBankPath: String?
    let outputJSON: Bool
}

struct RenderSummary {
    let midiDuration: Double
    let renderedDuration: Double
    let outputPath: String
}

struct PianoMIDIRenderer {
    func render(options: RenderOptions) throws -> RenderSummary {
        let fileManager = FileManager.default
        let inputURL = URL(fileURLWithPath: options.inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: options.outputPath).standardizedFileURL

        guard fileManager.fileExists(atPath: inputURL.path) else {
            throw CLIError.inputFileNotFound(inputURL.path)
        }

        let outputDirectory = outputURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: outputDirectory.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } else if !isDirectory.boolValue {
            throw CLIError.outputPathInvalid(outputURL.path)
        }

        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        let sequencer = AVAudioSequencer(audioEngine: engine)

        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)

        try loadPianoSoundBank(into: sampler, customPath: options.soundBankPath)
        try sequencer.load(from: inputURL)

        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }

        let midiDuration = max(sequencer.tracks.map(\.lengthInSeconds).max() ?? 0, 0)
        let renderedDuration = max(0.1, midiDuration + max(0, options.tailSeconds))

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: options.sampleRate,
            channels: 2,
            interleaved: true
        ) else {
            throw CLIError.engineFailure("Cannot create output audio format.")
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true
        )

        try engine.enableManualRenderingMode(
            .offline,
            format: outputFormat,
            maximumFrameCount: 4096
        )

        do {
            try engine.start()
            sequencer.currentPositionInSeconds = 0
            sequencer.prepareToPlay()
            try sequencer.start()

            try renderOffline(
                engine: engine,
                outputFile: outputFile,
                durationSeconds: renderedDuration,
                sampleRate: options.sampleRate
            )

            sequencer.stop()
            engine.stop()
            engine.disableManualRenderingMode()

            return RenderSummary(
                midiDuration: midiDuration,
                renderedDuration: renderedDuration,
                outputPath: outputURL.path
            )
        } catch {
            sequencer.stop()
            engine.stop()
            engine.disableManualRenderingMode()
            throw CLIError.engineFailure(error.localizedDescription)
        }
    }

    private func renderOffline(
        engine: AVAudioEngine,
        outputFile: AVAudioFile,
        durationSeconds: Double,
        sampleRate: Double
    ) throws {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else {
            throw CLIError.engineFailure("Cannot allocate render buffer.")
        }

        var framesRemaining = AVAudioFramePosition(durationSeconds * sampleRate)

        while framesRemaining > 0 {
            let framesToRender = AVAudioFrameCount(min(
                AVAudioFramePosition(buffer.frameCapacity),
                framesRemaining
            ))

            let status = try engine.renderOffline(framesToRender, to: buffer)

            switch status {
            case .success:
                try outputFile.write(from: buffer)
                framesRemaining -= AVAudioFramePosition(buffer.frameLength)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw CLIError.engineFailure("renderOffline returned .error")
            @unknown default:
                throw CLIError.engineFailure("renderOffline returned unknown status")
            }
        }
    }

    private func loadPianoSoundBank(into sampler: AVAudioUnitSampler, customPath: String?) throws {
        if let customPath {
            let customURL = URL(fileURLWithPath: customPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: customURL.path) else {
                throw CLIError.inputFileNotFound(customURL.path)
            }
            try sampler.loadSoundBankInstrument(
                at: customURL,
                program: 0,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            return
        }

        let candidatePaths = [
            "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls",
            "/System/Library/Components/DLSMusicDevice.component/Contents/Resources/DefaultBankGS.sf2"
        ]

        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            do {
                try sampler.loadSoundBankInstrument(
                    at: url,
                    program: 0,
                    bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                    bankLSB: 0
                )
                return
            } catch {
                continue
            }
        }

        throw CLIError.soundBankNotFound
    }
}

struct CLIParser {
    static func parse(arguments: [String]) throws -> Command {
        guard !arguments.isEmpty else {
            throw CLIError.missingCommand
        }

        let command = arguments[0]

        if command == "help" || command == "--help" || command == "-h" {
            return .help
        }

        guard command == "render" else {
            throw CLIError.unknownCommand(command)
        }

        var index = 1
        var inputPath: String?
        var outputPath: String?
        var tailSeconds: Double = 1.5
        var sampleRate: Double = 44_100
        var soundBankPath: String?
        var outputJSON = false

        while index < arguments.count {
            let arg = arguments[index]

            switch arg {
            case "--input", "-i":
                index += 1
                guard index < arguments.count else { throw CLIError.missingOptionValue(arg) }
                inputPath = arguments[index]

            case "--output", "-o":
                index += 1
                guard index < arguments.count else { throw CLIError.missingOptionValue(arg) }
                outputPath = arguments[index]

            case "--tail-seconds":
                index += 1
                guard index < arguments.count else { throw CLIError.missingOptionValue(arg) }
                guard let value = Double(arguments[index]) else {
                    throw CLIError.invalidNumber(option: arg, value: arguments[index])
                }
                tailSeconds = value

            case "--sample-rate":
                index += 1
                guard index < arguments.count else { throw CLIError.missingOptionValue(arg) }
                guard let value = Double(arguments[index]) else {
                    throw CLIError.invalidNumber(option: arg, value: arguments[index])
                }
                sampleRate = value

            case "--sound-bank":
                index += 1
                guard index < arguments.count else { throw CLIError.missingOptionValue(arg) }
                soundBankPath = arguments[index]

            case "--json":
                outputJSON = true

            case "--help", "-h":
                return .help

            default:
                throw CLIError.unknownCommand(arg)
            }

            index += 1
        }

        guard let inputPath else {
            throw CLIError.missingRequiredOption("--input")
        }

        guard let outputPath else {
            throw CLIError.missingRequiredOption("--output")
        }

        return .render(
            RenderOptions(
                inputPath: inputPath,
                outputPath: outputPath,
                tailSeconds: tailSeconds,
                sampleRate: sampleRate,
                soundBankPath: soundBankPath,
                outputJSON: outputJSON
            )
        )
    }

    static func usage() -> String {
        """
        pianokey-cli - MIDI to piano audio renderer

        Usage:
          pianokey-cli render --input <file.mid> --output <file.wav> [--tail-seconds 1.5] [--sample-rate 44100] [--sound-bank <bank.dls|bank.sf2>] [--json]
          pianokey-cli help

        Examples:
          pianokey-cli render -i ./song.mid -o ./song.wav
          pianokey-cli render -i ./song.mid -o ./song.wav --tail-seconds 2.0
          pianokey-cli render -i ./song.mid -o ./song.wav --json

        Notes:
          - Default instrument is Acoustic Grand Piano (program 0).
          - If your macOS lacks built-in banks, pass a custom bank via --sound-bank.
        """
    }
}

enum Command {
    case help
    case render(RenderOptions)
}

@main
struct PianoKeyCLI {
    static func main() {
        do {
            let command = try CLIParser.parse(arguments: Array(CommandLine.arguments.dropFirst()))

            switch command {
            case .help:
                print(CLIParser.usage())
                exit(CLIExitCode.success.rawValue)

            case .render(let options):
                let summary = try PianoMIDIRenderer().render(options: options)
                if options.outputJSON {
                    let payload: [String: Any] = [
                        "ok": true,
                        "midiDurationSeconds": summary.midiDuration,
                        "renderedDurationSeconds": summary.renderedDuration,
                        "outputPath": summary.outputPath
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                    if let text = String(data: data, encoding: .utf8) {
                        print(text)
                    }
                } else {
                    print("Rendered MIDI to WAV successfully.")
                    print("MIDI duration: \(String(format: "%.3f", summary.midiDuration))s")
                    print("Rendered duration: \(String(format: "%.3f", summary.renderedDuration))s")
                    print("Output: \(summary.outputPath)")
                }
                exit(CLIExitCode.success.rawValue)
            }
        } catch let error as CLIError {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            fputs("\n\(CLIParser.usage())\n", stderr)
            exit(error.exitCode.rawValue)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(CLIExitCode.runtimeFailure.rawValue)
        }
    }
}
