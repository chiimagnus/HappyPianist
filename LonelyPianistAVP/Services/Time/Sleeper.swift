import Foundation

protocol SleeperProtocol: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskSleeper: SleeperProtocol, Sendable {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
