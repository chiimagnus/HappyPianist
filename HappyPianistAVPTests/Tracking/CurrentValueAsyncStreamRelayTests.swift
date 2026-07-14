@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func cancellingAnOlderRelaySubscriberDoesNotDisconnectTheRemainingSubscriber() async {
    let relay = CurrentValueAsyncStreamRelay(0)
    let firstStream = relay.makeStream()
    let secondStream = relay.makeStream()
    let firstConsumerReady = AsyncStream<Void>.makeStream()

    let firstConsumer = Task { @MainActor in
        var isFirstValue = true
        for await _ in firstStream {
            guard Task.isCancelled == false else { return }
            if isFirstValue {
                isFirstValue = false
                firstConsumerReady.continuation.yield()
            }
        }
    }
    var secondIterator = secondStream.makeAsyncIterator()
    var firstConsumerReadyIterator = firstConsumerReady.stream.makeAsyncIterator()

    #expect(await secondIterator.next() == 0)
    _ = await firstConsumerReadyIterator.next()
    #expect(relay.activeSubscriberCount == 2)

    firstConsumer.cancel()
    _ = await firstConsumer.result
    for _ in 0 ..< 20 where relay.activeSubscriberCount != 1 {
        await Task.yield()
    }

    relay.yield(42)

    #expect(relay.activeSubscriberCount == 1)
    #expect(await secondIterator.next() == 42)
}

@MainActor
@Test
func finishingRelaySubscribersDoesNotPreventFutureSubscriptions() async {
    let relay = CurrentValueAsyncStreamRelay("initial")
    let oldStream = relay.makeStream()
    relay.finishSubscribers()
    relay.yield("latest")
    let newStream = relay.makeStream()

    var oldIterator = oldStream.makeAsyncIterator()
    var newIterator = newStream.makeAsyncIterator()

    #expect(await oldIterator.next() == "initial")
    #expect(await oldIterator.next() == nil)
    #expect(await newIterator.next() == "latest")
}
