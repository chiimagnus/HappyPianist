import Foundation
import os

final class AsyncStreamBroadcaster<Element: Sendable>: Sendable {
    private struct State {
        var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
        var isFinished = false
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State())

    func makeStream(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(2048)
    ) -> AsyncStream<Element> {
        let pair = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        let id = UUID()
        pair.continuation.onTermination = { [weak self] _ in
            self?.unregister(id: id)
        }

        let shouldFinish = stateLock.withLock { state in
            guard state.isFinished == false else { return true }
            state.continuations[id] = pair.continuation
            return false
        }
        if shouldFinish {
            pair.continuation.finish()
        }
        return pair.stream
    }

    @discardableResult
    func yield(_ element: Element) -> Int {
        let continuations = stateLock.withLock { state in
            state.isFinished ? [] : Array(state.continuations.values)
        }
        var droppedCount = 0
        for continuation in continuations {
            if case .dropped = continuation.yield(element) {
                droppedCount += 1
            }
        }
        return droppedCount
    }

    func finish() {
        let continuations = stateLock.withLock { state in
            guard state.isFinished == false else { return [AsyncStream<Element>.Continuation]() }
            state.isFinished = true
            let snapshot = Array(state.continuations.values)
            state.continuations.removeAll(keepingCapacity: false)
            return snapshot
        }
        for continuation in continuations {
            continuation.finish()
        }
    }

    private func unregister(id: UUID) {
        stateLock.withLock { state in
            state.continuations[id] = nil
        }
    }
}
