@testable import LonelyPianist
import Testing

@Suite("DebouncedActionScheduler")
@MainActor
struct DebouncedActionSchedulerTests {
    actor Counter {
        private(set) var value = 0
        func increment() {
            value += 1
        }
    }

    @Test("Coalesces multiple schedules into one action")
    func coalesces() async throws {
        let scheduler = DebouncedActionScheduler(debounce: .milliseconds(50))
        let counter = Counter()

        scheduler.schedule { Task { await counter.increment() } }
        scheduler.schedule { Task { await counter.increment() } }
        scheduler.schedule { Task { await counter.increment() } }

        try await Task.sleep(for: .milliseconds(120))
        #expect(await counter.value == 1)
    }

    @Test("Cancel prevents scheduled action from firing")
    func cancelStopsAction() async throws {
        let scheduler = DebouncedActionScheduler(debounce: .milliseconds(50))
        let counter = Counter()

        scheduler.schedule { Task { await counter.increment() } }
        scheduler.cancel()

        try await Task.sleep(for: .milliseconds(120))
        #expect(await counter.value == 0)
    }
}
