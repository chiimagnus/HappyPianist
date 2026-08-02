import Foundation

enum MIDISourceMonitoringConnectionState: Equatable {
    case idle
    case connected(sourceCount: Int)
    case failed(message: String)
}

@MainActor
protocol MIDISourceMonitoringServiceProtocol: AnyObject {
    var onConnectionStateChange: ((MIDISourceMonitoringConnectionState) -> Void)? { get set }
    var onSourceNamesChange: (([String]) -> Void)? { get set }
    var onLastErrorMessageChange: ((String?) -> Void)? { get set }

    func start() throws
    func stop()
    func refreshSources() throws
}
