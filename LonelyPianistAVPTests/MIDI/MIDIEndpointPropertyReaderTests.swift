import CoreMIDI
import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func stringPropertyReturnsNilWhenCoreMIDIReturnsError() {
    let adapter = MIDIEndpointPropertyReader.Adapter(
        getStringProperty: { _, _ in (kMIDIInvalidClient, nil) },
        getIntegerProperty: { _, _ in (noErr, 0) }
    )
    let reader = MIDIEndpointPropertyReader(adapter: adapter)

    #expect(reader.stringProperty(0, kMIDIPropertyName) == nil)
}

@Test
func stringPropertyReturnsNilWhenCoreMIDIReturnsNilValue() {
    let adapter = MIDIEndpointPropertyReader.Adapter(
        getStringProperty: { _, _ in (noErr, nil) },
        getIntegerProperty: { _, _ in (noErr, 0) }
    )
    let reader = MIDIEndpointPropertyReader(adapter: adapter)

    #expect(reader.stringProperty(0, kMIDIPropertyName) == nil)
}

@Test
func stringPropertyReturnsValueWhenCoreMIDIReturnsString() {
    let adapter = MIDIEndpointPropertyReader.Adapter(
        getStringProperty: { _, _ in (noErr, Unmanaged.passRetained("FakeName" as CFString)) },
        getIntegerProperty: { _, _ in (noErr, 0) }
    )
    let reader = MIDIEndpointPropertyReader(adapter: adapter)

    #expect(reader.stringProperty(0, kMIDIPropertyName) == "FakeName")
}

@Test
func int32PropertyReturnsNilWhenCoreMIDIReturnsError() {
    let adapter = MIDIEndpointPropertyReader.Adapter(
        getStringProperty: { _, _ in (noErr, nil) },
        getIntegerProperty: { _, _ in (kMIDIInvalidClient, 123) }
    )
    let reader = MIDIEndpointPropertyReader(adapter: adapter)

    #expect(reader.int32Property(0, kMIDIPropertyUniqueID) == nil)
}

@Test
func int32PropertyReturnsValueWhenCoreMIDIReturnsValue() {
    let adapter = MIDIEndpointPropertyReader.Adapter(
        getStringProperty: { _, _ in (noErr, nil) },
        getIntegerProperty: { _, _ in (noErr, 42) }
    )
    let reader = MIDIEndpointPropertyReader(adapter: adapter)

    #expect(reader.int32Property(0, kMIDIPropertyUniqueID) == 42)
}
