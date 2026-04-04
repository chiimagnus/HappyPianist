import CoreMIDI
import Foundation

enum MIDIOutTestError: LocalizedError {
    case invalidArguments(String)
    case noDestinations
    case destinationNotFound(String)
    case clientCreate(OSStatus)
    case outputPortCreate(OSStatus)
    case send(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            return message
        case .noDestinations:
            return "No MIDI destinations found. Is the device connected and recognized by macOS?"
        case .destinationNotFound(let query):
            return "No MIDI destination matched: \(query)"
        case .clientCreate(let status):
            return "Failed to create MIDI client (status: \(status))"
        case .outputPortCreate(let status):
            return "Failed to create MIDI output port (status: \(status))"
        case .send(let status):
            return "Failed to send MIDI message (status: \(status))"
        }
    }
}

struct Args {
    var listOnly = false
    var destinationIndex: Int?
    var destinationMatch: String?

    var channel: UInt8 = 1
    var note: UInt8 = 60
    var velocity: UInt8 = 100
    var durationMs: UInt64 = 300

    var quiet = false
}

private func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var displayName: Unmanaged<CFString>?
    let displayStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &displayName)
    if displayStatus == noErr, let displayName {
        return displayName.takeUnretainedValue() as String
    }

    var name: Unmanaged<CFString>?
    let nameStatus = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
    if nameStatus == noErr, let name {
        return name.takeUnretainedValue() as String
    }

    return "Unknown MIDI Destination"
}

private func listDestinations() -> [(index: Int, endpoint: MIDIEndpointRef, name: String)] {
    let count = MIDIGetNumberOfDestinations()
    return (0..<count).compactMap { index in
        let endpoint = MIDIGetDestination(index)
        guard endpoint != 0 else { return nil }
        return (index, endpoint, endpointName(endpoint))
    }
}

private func usage() -> String {
    """
    Usage:
      swift .github/scripts/midi-send-test.swift --list
      swift .github/scripts/midi-send-test.swift --dest <index> [--note 60] [--vel 100] [--chan 1] [--duration-ms 300]
      swift .github/scripts/midi-send-test.swift --match <substring> [--note 60] [--vel 100] [--chan 1] [--duration-ms 300]

    Notes:
      - Default is middle C (note 60), velocity 100, channel 1, duration 300ms.
      - This sends Note On then Note Off to the chosen destination.
    """
}

private func parseArgs(_ argv: [String]) throws -> Args {
    var args = Args()

    var i = 0
    while i < argv.count {
        let token = argv[i]
        switch token {
        case "--help", "-h":
            throw MIDIOutTestError.invalidArguments(usage())

        case "--list":
            args.listOnly = true

        case "--dest":
            guard i + 1 < argv.count, let value = Int(argv[i + 1]) else {
                throw MIDIOutTestError.invalidArguments("Missing or invalid value for --dest.\n\n\(usage())")
            }
            args.destinationIndex = value
            i += 1

        case "--match":
            guard i + 1 < argv.count else {
                throw MIDIOutTestError.invalidArguments("Missing value for --match.\n\n\(usage())")
            }
            args.destinationMatch = argv[i + 1]
            i += 1

        case "--note":
            guard i + 1 < argv.count, let value = Int(argv[i + 1]), (0...127).contains(value) else {
                throw MIDIOutTestError.invalidArguments("Missing or invalid value for --note (0~127).\n\n\(usage())")
            }
            args.note = UInt8(value)
            i += 1

        case "--vel":
            guard i + 1 < argv.count, let value = Int(argv[i + 1]), (0...127).contains(value) else {
                throw MIDIOutTestError.invalidArguments("Missing or invalid value for --vel (0~127).\n\n\(usage())")
            }
            args.velocity = UInt8(value)
            i += 1

        case "--chan":
            guard i + 1 < argv.count, let value = Int(argv[i + 1]), (1...16).contains(value) else {
                throw MIDIOutTestError.invalidArguments("Missing or invalid value for --chan (1~16).\n\n\(usage())")
            }
            args.channel = UInt8(value)
            i += 1

        case "--duration-ms":
            guard i + 1 < argv.count, let value = UInt64(argv[i + 1]) else {
                throw MIDIOutTestError.invalidArguments("Missing or invalid value for --duration-ms.\n\n\(usage())")
            }
            args.durationMs = value
            i += 1

        case "--quiet":
            args.quiet = true

        default:
            throw MIDIOutTestError.invalidArguments("Unknown argument: \(token)\n\n\(usage())")
        }
        i += 1
    }

    return args
}

private func resolveDestination(_ args: Args) throws -> (endpoint: MIDIEndpointRef, name: String) {
    let destinations = listDestinations()
    guard !destinations.isEmpty else { throw MIDIOutTestError.noDestinations }

    if args.listOnly {
        return (0, "")
    }

    if let index = args.destinationIndex {
        if let match = destinations.first(where: { $0.index == index }) {
            return (match.endpoint, match.name)
        }
        throw MIDIOutTestError.destinationNotFound("index=\(index)")
    }

    if let substring = args.destinationMatch?.trimmingCharacters(in: .whitespacesAndNewlines), !substring.isEmpty {
        if let match = destinations.first(where: { $0.name.localizedCaseInsensitiveContains(substring) }) {
            return (match.endpoint, match.name)
        }
        throw MIDIOutTestError.destinationNotFound(substring)
    }

    // Heuristic: if exactly one destination, use it.
    if destinations.count == 1 {
        return (destinations[0].endpoint, destinations[0].name)
    }

    throw MIDIOutTestError.invalidArguments(
        "Please choose a destination with --dest or --match.\n\n\(usage())"
    )
}

private func sendNote(
    outputPort: MIDIPortRef,
    destination: MIDIEndpointRef,
    channel: UInt8,
    note: UInt8,
    velocity: UInt8,
    isNoteOn: Bool
) throws {
    let status: UInt8 = (isNoteOn ? 0x90 : 0x80) | ((channel &- 1) & 0x0F)
    let data: [UInt8] = [status, note, velocity]

    let packetListPtr = UnsafeMutablePointer<MIDIPacketList>.allocate(capacity: 1)
    packetListPtr.initialize(to: MIDIPacketList())
    defer {
        packetListPtr.deinitialize(count: 1)
        packetListPtr.deallocate()
    }

    var packet = MIDIPacketListInit(packetListPtr)
    data.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        packet = MIDIPacketListAdd(packetListPtr, 1024, packet, 0, data.count, base)
    }

    let statusSend = MIDISend(outputPort, destination, packetListPtr)
    guard statusSend == noErr else { throw MIDIOutTestError.send(statusSend) }
}

do {
    let args = try parseArgs(Array(CommandLine.arguments.dropFirst()))

    let destinations = listDestinations()
    if args.listOnly {
        if destinations.isEmpty {
            throw MIDIOutTestError.noDestinations
        }
        for d in destinations {
            print("[\(d.index)] \(d.name)")
        }
        exit(0)
    }

    let resolved = try resolveDestination(args)
    var clientRef: MIDIClientRef = 0
    let statusClient = MIDIClientCreate("LonelyPianistMIDIOutTest" as CFString, nil, nil, &clientRef)
    guard statusClient == noErr else { throw MIDIOutTestError.clientCreate(statusClient) }
    defer { MIDIClientDispose(clientRef) }

    var outputPortRef: MIDIPortRef = 0
    let statusPort = MIDIOutputPortCreate(clientRef, "LonelyPianistMIDIOutTestOutput" as CFString, &outputPortRef)
    guard statusPort == noErr else { throw MIDIOutTestError.outputPortCreate(statusPort) }
    defer { MIDIPortDispose(outputPortRef) }

    if !args.quiet {
        print("Destination: \(resolved.name)")
        print("Sending: note=\(args.note) vel=\(args.velocity) chan=\(args.channel) durationMs=\(args.durationMs)")
    }

    try sendNote(
        outputPort: outputPortRef,
        destination: resolved.endpoint,
        channel: args.channel,
        note: args.note,
        velocity: args.velocity,
        isNoteOn: true
    )
    Thread.sleep(forTimeInterval: Double(args.durationMs) / 1000.0)
    try sendNote(
        outputPort: outputPortRef,
        destination: resolved.endpoint,
        channel: args.channel,
        note: args.note,
        velocity: 0,
        isNoteOn: false
    )

    if !args.quiet {
        print("Done.")
    }
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    fputs("\(message)\n", stderr)
    exit(1)
}
