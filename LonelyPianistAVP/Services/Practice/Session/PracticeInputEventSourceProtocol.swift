import Foundation

protocol PracticeInputEventSourceProtocol: AnyObject {
    var events: AsyncStream<PracticeInputEvent> { get }

    func start() throws
    func stop()
}

