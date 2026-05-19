import CoreMIDI
import Foundation

struct MIDIEndpointPropertyReader {
    struct Adapter: Sendable {
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
