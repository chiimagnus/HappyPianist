import Foundation

enum MIDIInputConnectionState: Equatable {
    case idle
    case connected(sourceCount: Int)
    case failed(String)
}

protocol MIDIInputServiceProtocol: AnyObject {
    var onEvent: (@Sendable (MIDIEvent) -> Void)? { get set }
    var onConnectionStateChange: (@Sendable (MIDIInputConnectionState) -> Void)? { get set }
    var onSourceNamesChange: (@Sendable ([String]) -> Void)? { get set }

    func start() throws
    func stop()
    func refreshSources() throws
}
