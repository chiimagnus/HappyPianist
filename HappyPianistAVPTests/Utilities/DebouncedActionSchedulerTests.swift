@testable import HappyPianistAVP
import os
import Testing

@Test
func debouncedActionSchedulerCancelPreventsPendingAction() async throws {
    let scheduler = DebouncedActionScheduler(debounce: .milliseconds(40))
    let counter = LockedInteger()

    scheduler.schedule { counter.increment() }
    scheduler.cancel()
    try await Task.sleep(for: .milliseconds(90))

    #expect(counter.value == 0)
}

@Test(.timeLimit(.minutes(1)))
func debouncedActionSchedulerRunsOnlyLatestAction() async {
    let scheduler = DebouncedActionScheduler(debounce: .milliseconds(40))
    let values = LockedIntegers()

    await withCheckedContinuation { completion in
        scheduler.schedule { values.append(1) }
        scheduler.schedule {
            values.append(2)
            completion.resume()
        }
    }
    withExtendedLifetime(scheduler) {}

    #expect(values.value == [2])
}

private final class LockedInteger: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    var value: Int {
        lock.withLock { $0 }
    }

    func increment() {
        lock.withLock { $0 += 1 }
    }
}

private final class LockedIntegers: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Int]())
    var value: [Int] {
        lock.withLock { $0 }
    }

    func append(_ value: Int) {
        lock.withLock { $0.append(value) }
    }
}
