import Foundation
import Testing

enum TestAsyncWait {
    // ponytail: polling is only for deterministic test doubles; production code must signal completion directly.
    static func until(
        _ description: String,
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while true {
            if await condition() { return }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for \(description) after \(timeout).")
                return
            }

            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                Issue.record("Cancelled while waiting for \(description).")
                return
            }
        }
    }
}
