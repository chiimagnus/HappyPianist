import CoreMIDI
import Foundation

enum MIDICanonicalProtocolSelection {
    static func subscribedProtocol(endpointProtocolID: MIDIProtocolID?, midi2PortAvailable: Bool) -> MIDIProtocolID {
        if endpointProtocolID == ._2_0, midi2PortAvailable {
            return ._2_0
        }
        return ._1_0
    }
}

enum MIDIEndpointConnectionPolicy {
    static func subscribedProtocol(endpointProtocolID: MIDIProtocolID?, midi2PortAvailable: Bool) -> MIDIProtocolID {
        guard endpointProtocolID == ._2_0, midi2PortAvailable else {
            return ._1_0
        }
        return ._2_0
    }
}

enum MIDISourceMonitoringConnectionState: Equatable {
    case idle
    case connected(sourceCount: Int)
    case failed(message: String)
}

protocol MIDISourceMonitoringServiceProtocol: AnyObject {
    var onConnectionStateChange: (@Sendable (MIDISourceMonitoringConnectionState) -> Void)? { get set }
    var onSourceNamesChange: (@Sendable ([String]) -> Void)? { get set }
    var onLastErrorMessageChange: (@Sendable (String?) -> Void)? { get set }

    func start() throws
    func stop()
    func refreshSources() throws
}

enum MIDI2ValueMapping {
    static func value16To7Bit(_ value: UInt16) -> Int {
        let scaled = (Double(value) / 65535.0 * 127.0).rounded()
        let resolved = max(0, min(127, Int(scaled)))
        guard value != 0 else { return 0 }
        return max(1, resolved)
    }

    static func value32To7Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 127.0).rounded()
        let resolved = max(0, min(127, Int(scaled)))
        guard value != 0 else { return 0 }
        return max(1, resolved)
    }

    static func pitchBend32To14Bit(_ value: UInt32) -> Int {
        let scaled = (Double(value) / Double(UInt32.max) * 16383.0).rounded()
        return max(0, min(16383, Int(scaled)))
    }
}

struct MIDI1MessageDecoder {
    func decode(_ message: MIDIUniversalMessage) -> MIDI1InputEvent.Kind? {
        guard message.type == .channelVoice1 else { return nil }

        let voice = message.channelVoice1
        switch voice.status {
        case .noteOn:
            let note = Int(voice.note.number)
            let velocity = Int(voice.note.velocity)
            if velocity == 0 {
                return .noteOff(note: note, velocity: 0)
            }
            return .noteOn(note: note, velocity: velocity)

        case .noteOff:
            let note = Int(voice.note.number)
            let velocity = Int(voice.note.velocity)
            return .noteOff(note: note, velocity: velocity)

        case .controlChange:
            let controller = Int(voice.controlChange.index)
            let value = Int(voice.controlChange.data)
            return .controlChange(controller: controller, value: value)

        case .programChange:
            return .programChange(program: Int(voice.program))

        case .channelPressure:
            return .channelPressure(value: Int(voice.channelPressure))

        case .polyPressure:
            return .polyPressure(
                note: Int(voice.polyPressure.noteNumber),
                value: Int(voice.polyPressure.pressure)
            )

        case .pitchBend:
            return .pitchBend(value: Int(voice.pitchBend))

        default:
            return nil
        }
    }
}

struct MIDI2MessageDecoder {
    func decode(_ message: MIDIUniversalMessage) -> MIDI2InputEvent.Kind? {
        guard message.type == .channelVoice2 else { return nil }

        let voice = message.channelVoice2
        switch voice.status {
        case .noteOn:
            return .noteOn(note: Int(voice.note.number), velocity16: voice.note.velocity)

        case .noteOff:
            return .noteOff(note: Int(voice.note.number), velocity16: voice.note.velocity)

        case .controlChange:
            return .controlChange(
                controller: Int(voice.controlChange.index),
                value32: UInt32(voice.controlChange.data)
            )

        case .programChange:
            return .programChange(program: Int(voice.programChange.program))

        case .channelPressure:
            return .channelPressure(value32: UInt32(voice.channelPressure.data))

        case .polyPressure:
            return .polyPressure(
                note: Int(voice.polyPressure.noteNumber),
                pressure32: UInt32(voice.polyPressure.pressure)
            )

        case .pitchBend:
            return .pitchBend(value32: UInt32(voice.pitchBend.data))

        default:
            return nil
        }
    }
}

struct MIDIEndpointPropertyReader {
    struct Adapter {
        var getStringProperty: @Sendable (MIDIEndpointRef, CFString) -> (OSStatus, Unmanaged<CFString>?)
        var getIntegerProperty: @Sendable (MIDIEndpointRef, CFString) -> (OSStatus, Int32)

        static let coreMIDI = Adapter(
            getStringProperty: { endpoint, property in
                var unmanagedValue: Unmanaged<CFString>?
                let status = MIDIObjectGetStringProperty(endpoint, property, &unmanagedValue)
                return (status, unmanagedValue)
            },
            getIntegerProperty: { endpoint, property in
                var value: Int32 = 0
                let status = MIDIObjectGetIntegerProperty(endpoint, property, &value)
                return (status, value)
            }
        )
    }

    private let adapter: Adapter

    init(adapter: Adapter = .coreMIDI) {
        self.adapter = adapter
    }

    func stringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        let (status, unmanagedValue) = adapter.getStringProperty(endpoint, property)
        guard status == noErr, let unmanagedValue else { return nil }

        // CoreMIDI returns the property value as a retained CFString.
        // Swift surfaces this via Unmanaged<CFString>, so we must claim the retain to avoid leaking.
        return unmanagedValue.takeRetainedValue() as String
    }

    func int32Property(_ endpoint: MIDIEndpointRef, _ property: CFString) -> Int32? {
        let (status, value) = adapter.getIntegerProperty(endpoint, property)
        guard status == noErr else { return nil }
        return value
    }

    static func stringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        MIDIEndpointPropertyReader().stringProperty(endpoint, property)
    }

    static func int32Property(_ endpoint: MIDIEndpointRef, _ property: CFString) -> Int32? {
        MIDIEndpointPropertyReader().int32Property(endpoint, property)
    }
}
