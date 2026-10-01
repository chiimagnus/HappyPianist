import ARKit
import Observation
import Synchronization
@testable import HappyPianistAVP
import Testing

@MainActor
@Test
func trackingLifecycleFactsInvalidateSpatialObservationConsumers() {
    let service = ARTrackingService()
    service.start(requirements: [.world])
    let tracking: any ARTrackingServiceProtocol = service
    let changes = Mutex(0)
    withObservationTracking {
        _ = tracking.providerStateByName
    } onChange: {
        changes.withLock { $0 += 1 }
    }
    service.stop()
    #expect(changes.withLock { $0 } == 1)

    withObservationTracking {
        _ = tracking.worldTrackingGeneration
    } onChange: {
        changes.withLock { $0 += 1 }
    }
    service.start(requirements: [.world])
    #expect(changes.withLock { $0 } == 2)
    service.stop()
}

@MainActor
@Test
func ordinaryRequirementChangesKeepStableWorldTrackingRuntime() {
    let service = ARTrackingService()

    service.start(requirements: [.world])
    let runtime = service.activeRuntime
    let generation = service.worldTrackingGeneration

    service.start(requirements: [.world, .hand])
    #expect(service.activeRuntime === runtime)
    #expect(service.activeRuntime?.worldTrackingProvider === runtime?.worldTrackingProvider)
    #expect(service.worldTrackingGeneration == generation)

    service.start(requirements: [.world])
    #expect(service.activeRuntime === runtime)
    #expect(service.activeRuntime?.worldTrackingProvider === runtime?.worldTrackingProvider)
    #expect(service.worldTrackingGeneration == generation)

    service.stop()
}

@MainActor
@Test
func fullStopThenRestartReplacesWorldTrackingGeneration() {
    let service = ARTrackingService()

    service.start(requirements: [.world])
    let firstRuntime = service.activeRuntime
    let firstGeneration = service.worldTrackingGeneration

    service.stop()
    service.start(requirements: [.world])
    let secondRuntime = service.activeRuntime

    #expect(firstRuntime != nil)
    #expect(secondRuntime != nil)
    #expect(firstRuntime !== secondRuntime)
    #expect(firstRuntime?.session !== secondRuntime?.session)
    #expect(firstRuntime?.worldTrackingProvider !== secondRuntime?.worldTrackingProvider)
    #expect(service.worldTrackingGeneration == firstGeneration + 1)

    service.stop()
}

@MainActor
@Test
func queuedReconciliationCannotAdoptARuntimeCreatedAfterRestart() async {
    let service = ARTrackingService()
    service.start(requirements: [.world])
    let firstRuntime = service.activeRuntime
    service.stop()
    service.start(requirements: [.world])
    let replacement = service.activeRuntime
    let generation = service.worldTrackingGeneration
    service.start(requirements: [.world, .hand])
    await Task.yield()
    #expect(firstRuntime !== replacement)
    #expect(service.activeRuntime === replacement)
    #expect(service.worldTrackingGeneration == generation)
    service.start(requirements: [.world])
    await Task.yield()
    #expect(service.activeRuntime === replacement)
    service.stop()
}

@MainActor
@Test
func stoppingTrackingClearsHandSkeletonWithoutFinishingStreams() async {
    let service = ARTrackingService()
    var iterator = service.handSkeletonUpdatesStream().makeAsyncIterator()

    #expect(await iterator.next() == .empty)
    service.start(requirements: [.hand, .world])
    service.stop()

    #expect(service.handSkeletonSnapshot == .empty)
    #expect(await iterator.next() == .empty)
}

@MainActor
@Test
func providerStateMappingPreservesPausedAndStoppedFacts() {
    #expect(ARTrackingService.trackingState(for: .initialized) == .idle)
    #expect(ARTrackingService.trackingState(for: .running) == .running)
    #expect(ARTrackingService.trackingState(for: .paused) == .paused)
    #expect(ARTrackingService.trackingState(for: .stopped) == .stopped)
}

@MainActor
@Test
func authorizationStateMappingDoesNotInventRunningState() {
    #expect(ARTrackingService.trackingState(for: ARKitSession.AuthorizationStatus.allowed) == nil)
    #expect(
        ARTrackingService.trackingState(for: ARKitSession.AuthorizationStatus.notDetermined)
            == .unauthorized
    )
    #expect(
        ARTrackingService.trackingState(for: ARKitSession.AuthorizationStatus.denied)
            == .unauthorized
    )
}
