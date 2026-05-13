import Dispatch
import Foundation

final class DebouncedActionScheduler: @unchecked Sendable {
    private let queue: DispatchQueue
    private let debounceSec: TimeInterval
    private var workItem: DispatchWorkItem?

    init(queue: DispatchQueue, debounceSec: TimeInterval) {
        self.queue = queue
        self.debounceSec = max(0, debounceSec)
    }

    func schedule(_ action: @escaping @Sendable () -> Void) {
        workItem?.cancel()

        let item = DispatchWorkItem(block: action)
        workItem = item

        queue.asyncAfter(deadline: .now() + debounceSec, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

