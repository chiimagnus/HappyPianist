import Foundation

protocol PracticeInputEventSourceProtocol: AnyObject {
    func eventsStream() -> AsyncStream<PracticeInputEvent>

    func start() throws
    func stop()
}
