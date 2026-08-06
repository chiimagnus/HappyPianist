@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func restartingTrackingReplacesStoppedARKitProviders() {
    let service = ARTrackingService()

    service.start(requirements: [.world])
    let firstRuntime = service.activeRuntime

    service.stop()
    service.start(requirements: [.world])
    let secondRuntime = service.activeRuntime

    #expect(firstRuntime != nil)
    #expect(secondRuntime != nil)
    #expect(firstRuntime !== secondRuntime)
    #expect(firstRuntime?.session !== secondRuntime?.session)
    #expect(firstRuntime?.worldTrackingProvider !== secondRuntime?.worldTrackingProvider)
    #expect(firstRuntime?.handTrackingProvider !== secondRuntime?.handTrackingProvider)
    #expect(firstRuntime?.planeDetectionProvider !== secondRuntime?.planeDetectionProvider)

    service.stop()
}

@MainActor
@Test
func stoppingTrackingClearsHandSkeletonSnapshot() async {
    let service = ARTrackingService()
    var iterator = service.handSkeletonUpdatesStream().makeAsyncIterator()

    #expect(await iterator.next() == .empty)
    service.start(requirements: [.hand])
    #expect(await iterator.next() == .empty)
    service.stop()

    #expect(service.handSkeletonSnapshot == .empty)
    #expect(await iterator.next() == .empty)
    #expect(await iterator.next() == nil)
}
