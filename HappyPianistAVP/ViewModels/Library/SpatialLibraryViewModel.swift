import Foundation
import Observation

@MainActor
@Observable
final class SpatialLibraryViewModel {
    enum State: Equatable {
        case inactive
        case awaitingDevicePose
        case placed(SpatialLibraryPlacement)
        case placementFailed(SpatialLibraryPlacementFailure)
    }

    private(set) var state: State = .inactive

    private let arTrackingService: any ARTrackingServiceProtocol
    private let placementResolver: SpatialLibraryPlacementResolver
    private let placementTimeout: Duration
    private let pollingInterval: Duration

    @ObservationIgnored private var placementTask: Task<Void, Never>?
    @ObservationIgnored private var cachedPlacement: SpatialLibraryPlacement?

    init(
        arTrackingService: any ARTrackingServiceProtocol,
        placementResolver: SpatialLibraryPlacementResolver = SpatialLibraryPlacementResolver(),
        placementTimeout: Duration = .seconds(5),
        pollingInterval: Duration = .milliseconds(250)
    ) {
        self.arTrackingService = arTrackingService
        self.placementResolver = placementResolver
        self.placementTimeout = placementTimeout
        self.pollingInterval = pollingInterval
    }

    func enterLibraryMode() {
        cancelPlacementTask()

        if let cachedPlacement,
           cachedPlacement.worldTrackingGeneration == arTrackingService.worldTrackingGeneration,
           arTrackingService.providerStateByName["world"] == .running
        {
            state = .placed(cachedPlacement)
            return
        }

        if cachedPlacement?.worldTrackingGeneration != arTrackingService.worldTrackingGeneration {
            self.cachedPlacement = nil
        }

        state = .awaitingDevicePose
        placementTask = Task { @MainActor [weak self] in
            await self?.resolvePlacement()
        }
    }

    func leaveLibraryMode() {
        cancelPlacementTask()
        if case .placed = state {
            return
        }
        state = .inactive
    }

    func retryPlacement() {
        enterLibraryMode()
    }

    func invalidatePlacement() {
        cancelPlacementTask()
        cachedPlacement = nil
        state = .inactive
    }

    private func resolvePlacement() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: placementTimeout)

        while Task.isCancelled == false {
            if let failure = immediateFailure() {
                state = .placementFailed(failure)
                placementTask = nil
                return
            }

            if let cachedPlacement,
               cachedPlacement.worldTrackingGeneration == arTrackingService.worldTrackingGeneration,
               arTrackingService.providerStateByName["world"] == .running
            {
                state = .placed(cachedPlacement)
                placementTask = nil
                return
            }

            if arTrackingService.providerStateByName["world"] == .running,
               let deviceTransform = arTrackingService.deviceWorldTransform(
                   atTimestamp: ProcessInfo.processInfo.systemUptime
               ),
               let worldFromSpatialLibrary = placementResolver.resolve(
                   deviceWorldTransform: deviceTransform
               )
            {
                let placement = SpatialLibraryPlacement(
                    worldFromSpatialLibrary: worldFromSpatialLibrary,
                    worldTrackingGeneration: arTrackingService.worldTrackingGeneration
                )
                cachedPlacement = placement
                state = .placed(placement)
                placementTask = nil
                return
            }

            if clock.now >= deadline {
                state = .placementFailed(.timedOut)
                placementTask = nil
                return
            }

            do {
                try await Task.sleep(for: pollingInterval)
            } catch {
                return
            }
        }
    }

    private func immediateFailure() -> SpatialLibraryPlacementFailure? {
        guard arTrackingService.isWorldTrackingSupported else {
            return .worldTrackingUnsupported
        }

        return switch arTrackingService.providerStateByName["world"] ?? .idle {
        case .unsupported:
            .worldTrackingUnsupported
        case .unauthorized:
            .worldTrackingUnauthorized
        case let .failed(reason):
            .worldTrackingFailed(reason: reason)
        case .idle, .running, .paused, .disabled, .stopped:
            nil
        }
    }

    private func cancelPlacementTask() {
        placementTask?.cancel()
        placementTask = nil
    }
}
