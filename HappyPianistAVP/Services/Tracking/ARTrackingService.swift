import ARKit
import Foundation
import simd

enum ARTrackingServiceError: LocalizedError {
    case worldTrackingNotRunning

    var errorDescription: String? {
        switch self {
        case .worldTrackingNotRunning:
            "世界追踪尚未运行，无法管理空间锚点。"
        }
    }
}

@MainActor
final class ARTrackingService: ARTrackingServiceProtocol {
    private(set) var fingerTipsSnapshot = FingerTipsSnapshot.empty
    private(set) var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    private(set) var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    private(set) var detectedPlanes: [DetectedPlane] = []
    private(set) var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] = [:]
    private(set) var providerStateByName: [String: DataProviderState] = [
        "hand": .idle,
        "world": .idle,
        "plane": .idle,
    ]
    private(set) var activeRequirements: ARTrackingRequirements = []

    var isWorldTrackingSupported: Bool {
        WorldTrackingProvider.isSupported
    }

    private let session = ARKitSession()
    private let worldTrackingProvider = WorldTrackingProvider()
    private let handTrackingProvider = HandTrackingProvider()
    private let planeDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal])
    private let fingerTipUpdates = CurrentValueAsyncStreamRelay(FingerTipsSnapshot.empty)

    private var sessionTask: Task<Void, Never>?
    private var handUpdatesTask: Task<Void, Never>?
    private var worldAnchorUpdatesTask: Task<Void, Never>?
    private var planeAnchorUpdatesTask: Task<Void, Never>?
    private var sessionGeneration = 0
    private var isSessionRunning = false

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot> {
        fingerTipUpdates.makeStream()
    }

    func deviceWorldTransform(atTimestamp timestamp: TimeInterval) -> simd_float4x4? {
        guard providerStateByName["world"] == .running,
              let anchor = worldTrackingProvider.queryDeviceAnchor(atTimestamp: timestamp),
              anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
    }

    func addWorldAnchor(originFromAnchorTransform: simd_float4x4) async throws -> UUID {
        guard providerStateByName["world"] == .running else {
            throw ARTrackingServiceError.worldTrackingNotRunning
        }
        let anchor = WorldAnchor(originFromAnchorTransform: originFromAnchorTransform)
        try await worldTrackingProvider.addAnchor(anchor)
        return anchor.id
    }

    func removeWorldAnchor(id: UUID) async throws {
        guard providerStateByName["world"] == .running else {
            throw ARTrackingServiceError.worldTrackingNotRunning
        }
        try await worldTrackingProvider.removeAnchor(forID: id)
    }

    func start(requirements: ARTrackingRequirements) {
        if requirements == activeRequirements, sessionTask != nil || isSessionRunning {
            return
        }

        sessionGeneration += 1
        let generation = sessionGeneration
        stopProviderRuntime()
        activeRequirements = requirements
        clearStateForDisabledProviders(requirements: requirements)
        configureInitialProviderStates(requirements: requirements)

        guard requirements.isEmpty == false else { return }

        sessionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if sessionGeneration == generation {
                    sessionTask = nil
                }
            }

            let includesHand = requirements.contains(.hand)
            let includesWorld = requirements.contains(.world)
            let includesPlane = requirements.contains(.horizontalPlanes)

            let handSupported = includesHand && HandTrackingProvider.isSupported
            let worldSupported = includesWorld && WorldTrackingProvider.isSupported
            let planeSupported = includesPlane && PlaneDetectionProvider.isSupported

            let handAuthorizations = handSupported ? HandTrackingProvider.requiredAuthorizations : []
            let worldAuthorizations = worldSupported ? WorldTrackingProvider.requiredAuthorizations : []
            let planeAuthorizations = planeSupported ? PlaneDetectionProvider.requiredAuthorizations : []
            let requiredAuthorizations = deduplicatedRequiredAuthorizations(
                includeHand: handSupported,
                includeWorld: worldSupported,
                includePlane: planeSupported
            )
            let statuses: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] =
                requiredAuthorizations.isEmpty ? [:] : await session.requestAuthorization(for: requiredAuthorizations)

            guard Task.isCancelled == false, sessionGeneration == generation else { return }
            authorizationStatusByType = statuses

            let handAllowed = handSupported && isAuthorized(
                requiredAuthorizations: handAuthorizations,
                statuses: statuses
            )
            let worldAllowed = worldSupported && isAuthorized(
                requiredAuthorizations: worldAuthorizations,
                statuses: statuses
            )
            let planeAllowed = planeSupported && isAuthorized(
                requiredAuthorizations: planeAuthorizations,
                statuses: statuses
            )

            updateAuthorizationStates(
                requirements: requirements,
                handSupported: handSupported,
                worldSupported: worldSupported,
                planeSupported: planeSupported,
                handAllowed: handAllowed,
                worldAllowed: worldAllowed,
                planeAllowed: planeAllowed
            )

            var providersToRun: [any DataProvider] = []
            if handAllowed { providersToRun.append(handTrackingProvider) }
            if worldAllowed { providersToRun.append(worldTrackingProvider) }
            if planeAllowed { providersToRun.append(planeDetectionProvider) }
            guard providersToRun.isEmpty == false else { return }

            do {
                try await session.run(providersToRun)
                guard Task.isCancelled == false, sessionGeneration == generation else {
                    session.stop()
                    return
                }
                isSessionRunning = true
                if handAllowed { providerStateByName["hand"] = .running }
                if worldAllowed { providerStateByName["world"] = .running }
                if planeAllowed { providerStateByName["plane"] = .running }
                startUpdateTasks(generation: generation)
            } catch {
                guard sessionGeneration == generation else { return }
                isSessionRunning = false
                if error is CancellationError {
                    markRunningProvidersStopped()
                } else {
                    if handAllowed { providerStateByName["hand"] = .failed(reason: error.localizedDescription) }
                    if worldAllowed { providerStateByName["world"] = .failed(reason: error.localizedDescription) }
                    if planeAllowed { providerStateByName["plane"] = .failed(reason: error.localizedDescription) }
                }
            }
        }
    }

    func stop() {
        sessionGeneration += 1
        stopProviderRuntime()
        activeRequirements = []
        fingerTipUpdates.finishSubscribers()
        clearAllTrackingState()
        markRunningProvidersStopped()
    }

    private func stopProviderRuntime() {
        handUpdatesTask?.cancel()
        worldAnchorUpdatesTask?.cancel()
        planeAnchorUpdatesTask?.cancel()
        sessionTask?.cancel()

        handUpdatesTask = nil
        worldAnchorUpdatesTask = nil
        planeAnchorUpdatesTask = nil
        sessionTask = nil

        session.stop()
        isSessionRunning = false
    }

    private func clearAllTrackingState() {
        fingerTipsSnapshot = .empty
        fingerTipUpdates.yield(.empty)
        worldAnchorsByID.removeAll(keepingCapacity: false)
        planeAnchorsByID.removeAll(keepingCapacity: false)
        detectedPlanes.removeAll(keepingCapacity: false)
    }

    private func clearStateForDisabledProviders(requirements: ARTrackingRequirements) {
        if requirements.contains(.hand) == false {
            fingerTipsSnapshot = .empty
            fingerTipUpdates.yield(.empty)
        }
        if requirements.contains(.world) == false {
            worldAnchorsByID.removeAll(keepingCapacity: false)
        }
        if requirements.contains(.horizontalPlanes) == false {
            planeAnchorsByID.removeAll(keepingCapacity: false)
            detectedPlanes.removeAll(keepingCapacity: false)
        }
    }

    private func configureInitialProviderStates(requirements: ARTrackingRequirements) {
        providerStateByName["hand"] = initialState(
            isRequired: requirements.contains(.hand),
            isSupported: HandTrackingProvider.isSupported
        )
        providerStateByName["world"] = initialState(
            isRequired: requirements.contains(.world),
            isSupported: WorldTrackingProvider.isSupported
        )
        providerStateByName["plane"] = initialState(
            isRequired: requirements.contains(.horizontalPlanes),
            isSupported: PlaneDetectionProvider.isSupported
        )
    }

    private func initialState(isRequired: Bool, isSupported: Bool) -> DataProviderState {
        guard isRequired else { return .disabled }
        return isSupported ? .idle : .unsupported
    }

    private func updateAuthorizationStates(
        requirements: ARTrackingRequirements,
        handSupported: Bool,
        worldSupported: Bool,
        planeSupported: Bool,
        handAllowed: Bool,
        worldAllowed: Bool,
        planeAllowed: Bool
    ) {
        if requirements.contains(.hand), handSupported, handAllowed == false {
            providerStateByName["hand"] = .unauthorized
        }
        if requirements.contains(.world), worldSupported, worldAllowed == false {
            providerStateByName["world"] = .unauthorized
        }
        if requirements.contains(.horizontalPlanes), planeSupported, planeAllowed == false {
            providerStateByName["plane"] = .unauthorized
        }
    }

    private func markRunningProvidersStopped() {
        for name in ["hand", "world", "plane"] where providerStateByName[name] == .running {
            providerStateByName[name] = .stopped
        }
    }

    private func startUpdateTasks(generation: Int) {
        if handUpdatesTask == nil, providerStateByName["hand"] == .running {
            handUpdatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in handTrackingProvider.anchorUpdates {
                    guard Task.isCancelled == false, sessionGeneration == generation else { return }
                    updateFingerTips(from: update.anchor)
                }
            }
        }

        if worldAnchorUpdatesTask == nil, providerStateByName["world"] == .running {
            worldAnchorUpdatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in worldTrackingProvider.anchorUpdates {
                    guard Task.isCancelled == false, sessionGeneration == generation else { return }
                    switch update.event {
                    case .removed:
                        worldAnchorsByID.removeValue(forKey: update.anchor.id)
                    case .added, .updated:
                        worldAnchorsByID[update.anchor.id] = update.anchor
                    @unknown default:
                        worldAnchorsByID[update.anchor.id] = update.anchor
                    }
                }
            }
        }

        if planeAnchorUpdatesTask == nil, providerStateByName["plane"] == .running {
            planeAnchorUpdatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in planeDetectionProvider.anchorUpdates {
                    guard Task.isCancelled == false, sessionGeneration == generation else { return }
                    switch update.event {
                    case .removed:
                        planeAnchorsByID.removeValue(forKey: update.anchor.id)
                    case .added, .updated:
                        planeAnchorsByID[update.anchor.id] = update.anchor
                    @unknown default:
                        planeAnchorsByID[update.anchor.id] = update.anchor
                    }
                    rebuildDetectedPlanes()
                }
            }
        }
    }

    private func updateFingerTips(from anchor: HandAnchor) {
        let side: TrackedHandSide
        switch anchor.chirality {
        case .left:
            side = .left
        case .right:
            side = .right
        @unknown default:
            return
        }

        fingerTipsSnapshot[side] = anchor.isTracked ? extractHandTips(from: anchor) : HandTips()
        fingerTipUpdates.yield(fingerTipsSnapshot)
    }

    private func rebuildDetectedPlanes() {
        detectedPlanes = planeAnchorsByID.values.map { anchor in
            DetectedPlane(id: anchor.id, worldFromPlane: anchor.originFromAnchorTransform)
        }
    }

    private func deduplicatedRequiredAuthorizations(
        includeHand: Bool,
        includeWorld: Bool,
        includePlane: Bool
    ) -> [ARKitSession.AuthorizationType] {
        var seen: Set<ARKitSession.AuthorizationType> = []
        var ordered: [ARKitSession.AuthorizationType] = []
        var required: [ARKitSession.AuthorizationType] = []

        if includeHand { required += HandTrackingProvider.requiredAuthorizations }
        if includeWorld { required += WorldTrackingProvider.requiredAuthorizations }
        if includePlane { required += PlaneDetectionProvider.requiredAuthorizations }

        for type in required where seen.insert(type).inserted {
            ordered.append(type)
        }
        return ordered
    }

    private func isAuthorized(
        requiredAuthorizations: [ARKitSession.AuthorizationType],
        statuses: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus]
    ) -> Bool {
        requiredAuthorizations.allSatisfy { statuses[$0] == .allowed }
    }

    private func extractHandTips(from anchor: HandAnchor) -> HandTips {
        guard let handSkeleton = anchor.handSkeleton else { return HandTips() }

        func trackedPoint(_ jointName: HandSkeleton.JointName) -> SIMD3<Float>? {
            let joint = handSkeleton.joint(jointName)
            guard joint.isTracked else { return nil }
            let transform = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }

        var tips = HandTips(
            thumb: trackedPoint(.thumbTip),
            index: trackedPoint(.indexFingerTip),
            middle: trackedPoint(.middleFingerTip),
            ring: trackedPoint(.ringFingerTip),
            little: trackedPoint(.littleFingerTip),
            palm: nil
        )

        var palmSum = SIMD3<Float>(repeating: 0)
        var palmCount: Float = 0
        func includePalmJoint(_ jointName: HandSkeleton.JointName) {
            guard let point = trackedPoint(jointName) else { return }
            palmSum += point
            palmCount += 1
        }

        includePalmJoint(.wrist)
        includePalmJoint(.thumbKnuckle)
        includePalmJoint(.indexFingerMetacarpal)
        includePalmJoint(.middleFingerMetacarpal)
        includePalmJoint(.ringFingerMetacarpal)
        includePalmJoint(.littleFingerMetacarpal)
        if palmCount > 0 {
            tips.palm = palmSum / palmCount
        }
        return tips
    }
}
