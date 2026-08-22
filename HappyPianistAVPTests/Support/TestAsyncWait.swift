import Foundation
import Testing

enum TestAsyncWait {
    // 轮询仅用于确定性测试替身；生产代码必须以完成信号同步。
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
