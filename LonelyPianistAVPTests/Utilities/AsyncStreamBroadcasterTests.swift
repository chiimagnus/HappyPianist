import Foundation
@testable import LonelyPianistAVP
import Testing

private struct TestEvent: Equatable, Sendable {
    let id: Int
    let value: Int
}

@Test
func broadcasterDeliversSameEventToMultipleConsumers() async {
    let broadcaster = AsyncStreamBroadcaster<TestEvent>()
    let streamA = broadcaster.makeStream()
    let streamB = broadcaster.makeStream()

    async let firstA = streamA.first(where: { _ in true })
    async let firstB = streamB.first(where: { _ in true })

    for _ in 0 ..< 20 {
        await Task.yield()
    }

    broadcaster.yield(TestEvent(id: 1, value: 42))

    let receivedA = await firstA
    let receivedB = await firstB

    #expect(receivedA == TestEvent(id: 1, value: 42))
    #expect(receivedB == TestEvent(id: 1, value: 42))
}

@Test
func cancellingOneConsumerDoesNotAffectOtherConsumers() async {
    let broadcaster = AsyncStreamBroadcaster<TestEvent>()
    let streamA = broadcaster.makeStream()
    let streamB = broadcaster.makeStream()

    let consumerA = Task {
        var iterator = streamA.makeAsyncIterator()
        _ = await iterator.next()
        return "done"
    }

    let consumerB = Task {
        var iterator = streamB.makeAsyncIterator()
        return await iterator.next()
    }

    consumerA.cancel()

    for _ in 0 ..< 20 {
        await Task.yield()
    }

    broadcaster.yield(TestEvent(id: 2, value: 99))

    let receivedB = await consumerB.value
    #expect(receivedB == TestEvent(id: 2, value: 99))
}
