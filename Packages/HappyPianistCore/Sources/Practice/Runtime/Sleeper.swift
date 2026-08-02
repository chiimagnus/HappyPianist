import Foundation

public protocol SleeperProtocol: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: SleeperProtocol {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
