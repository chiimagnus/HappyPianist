import Foundation
import os

final class DebouncedActionScheduler: Sendable {
    private struct State {
        var generation: UInt64 = 0
        var task: Task<Void, Never>?
    }

    private let debounce: Duration
    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    init(debounce: Duration) {
        self.debounce = debounce
    }

    func schedule(_ action: @escaping @Sendable () -> Void) {
        let debounce = debounce
        stateLock.withLock { state in
            state.generation &+= 1
            let generation = state.generation
            state.task?.cancel()
            state.task = Task { [weak self] in
                do {
                    try await Task.sleep(for: debounce)
                } catch {
                    return
                }

                guard let self else { return }
                let shouldRun = self.stateLock.withLock { state in
                    guard state.generation == generation else { return false }
                    state.task = nil
                    return true
                }
                if shouldRun {
                    action()
                }
            }
        }
    }

    func cancel() {
        stateLock.withLock { state in
            state.generation &+= 1
            state.task?.cancel()
            state.task = nil
        }
    }
}
