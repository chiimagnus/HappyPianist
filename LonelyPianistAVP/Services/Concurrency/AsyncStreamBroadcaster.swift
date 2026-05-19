import Foundation

actor AsyncStreamBroadcaster<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    nonisolated func makeStream(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Element> {
        AsyncStream(Element.self, bufferingPolicy: bufferingPolicy) { continuation in
            let id = UUID()
            Task {
                await self.register(continuation, id: id)
            }

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.unregister(id: id)
                }
            }
        }
    }

    nonisolated func yield(_ element: Element) {
        Task {
            await self.yieldIsolated(element)
        }
    }

    nonisolated func finish() {
        Task {
            await self.finishIsolated()
        }
    }

    private func register(_ continuation: AsyncStream<Element>.Continuation, id: UUID) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    private func yieldIsolated(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    private func finishIsolated() {
        let snapshot = continuations.values
        continuations.removeAll(keepingCapacity: true)
        for continuation in snapshot {
            continuation.finish()
        }
    }
}
