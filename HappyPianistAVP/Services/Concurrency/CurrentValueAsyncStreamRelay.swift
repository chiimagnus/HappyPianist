import Foundation

@MainActor
final class CurrentValueAsyncStreamRelay<Element: Sendable> {
    private var currentValue: Element
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    init(_ initialValue: Element) {
        currentValue = initialValue
    }

    var activeSubscriberCount: Int {
        continuations.count
    }

    func makeStream() -> AsyncStream<Element> {
        let id = UUID()
        let pair = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(1))
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.continuations[id] = nil
            }
        }
        continuations[id] = pair.continuation
        pair.continuation.yield(currentValue)
        return pair.stream
    }

    func yield(_ value: Element) {
        currentValue = value
        for continuation in continuations.values {
            continuation.yield(value)
        }
    }

    func finishSubscribers() {
        let subscribers = Array(continuations.values)
        continuations.removeAll(keepingCapacity: false)
        for continuation in subscribers {
            continuation.finish()
        }
    }
}
