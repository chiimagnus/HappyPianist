import Foundation

public protocol MIDIInputEventSource: AnyObject {
    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent>
    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent>

    func start() throws
    func stop()
}
