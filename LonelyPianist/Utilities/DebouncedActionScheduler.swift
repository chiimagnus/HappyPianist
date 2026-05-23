import Foundation
import os

final nonisolated class DebouncedActionScheduler: @unchecked Sendable {
    private struct State {
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
            state.task?.cancel()
            state.task = Task {
                try? await Task.sleep(for: debounce)
                guard Task.isCancelled == false else { return }
                action()
            }
        }
    }

    func cancel() {
        stateLock.withLock { state in
            state.task?.cancel()
            state.task = nil
        }
    }
}
