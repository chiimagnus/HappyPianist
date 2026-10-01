import ARKit
@testable import HappyPianistAVP
import Testing

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
