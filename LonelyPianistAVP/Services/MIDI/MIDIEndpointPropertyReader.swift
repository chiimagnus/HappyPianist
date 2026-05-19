import CoreMIDI
import Foundation

struct MIDIEndpointPropertyReader {
    static func stringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        var unmanagedString: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, property, &unmanagedString)
        guard status == noErr else { return nil }

        // CoreMIDI returns the property value as a retained CFString.
        // Swift surfaces this via Unmanaged<CFString>, so we must claim the retain to avoid leaking.
        return unmanagedString?.takeRetainedValue() as String?
    }

    static func int32Property(_ endpoint: MIDIEndpointRef, _ property: CFString) -> Int32? {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(endpoint, property, &value)
        guard status == noErr else { return nil }
        return value
    }
}

