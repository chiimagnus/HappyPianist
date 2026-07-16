import Foundation
@testable import HappyPianistAVP
import Testing

private struct TestEvent: Equatable {
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

@Test
func broadcasterDoesNotLoseImmediateYield() async {
    let broadcaster = AsyncStreamBroadcaster<Int>()
    let stream = broadcaster.makeStream(bufferingPolicy: .bufferingNewest(1))
    broadcaster.yield(42)

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == 42)
}

@Test
func broadcasterFinishEndsCurrentAndFutureStreams() async {
    let broadcaster = AsyncStreamBroadcaster<Int>()
    let current = broadcaster.makeStream()
    broadcaster.finish()
    let future = broadcaster.makeStream()

    var currentIterator = current.makeAsyncIterator()
    var futureIterator = future.makeAsyncIterator()
    #expect(await currentIterator.next() == nil)
    #expect(await futureIterator.next() == nil)
}

@Test
func broadcasterReportsOverflowAndKeepsNewestElement() async {
    let broadcaster = AsyncStreamBroadcaster<Int>()
    let stream = broadcaster.makeStream(bufferingPolicy: .bufferingNewest(1))

    #expect(broadcaster.yield(1) == 0)
    #expect(broadcaster.yield(2) == 1)

    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == 2)
}
