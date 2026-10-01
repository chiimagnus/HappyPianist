import ARKit
import Foundation
import Observation
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
@Observable
final class ARTrackingService: ARTrackingServiceProtocol {
    final class Runtime {
        let session = ARKitSession()
        let worldTrackingProvider = WorldTrackingProvider()
        var handTrackingProvider: HandTrackingProvider?
        var planeDetectionProvider: PlaneDetectionProvider?
    }

    private enum ProviderKind: String {
        case hand
        case world
        case plane

        var requirement: ARTrackingRequirements {
            switch self {
            case .hand: .hand
            case .world: .world
            case .plane: .horizontalPlanes
            }
        }
    }

    private(set) var fingerTipsSnapshot = FingerTipsSnapshot.empty
    private(set) var handSkeletonSnapshot = HandSkeletonSnapshot.empty
    private(set) var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    private(set) var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    private(set) var detectedPlanes: [DetectedPlane] = []
    private(set) var providerStateByName: [String: ARTrackingProviderState] = [
        ProviderKind.hand.rawValue: .idle,
        ProviderKind.world.rawValue: .idle,
        ProviderKind.plane.rawValue: .idle,
    ]
    private(set) var worldTrackingGeneration = 0

    var isWorldTrackingSupported: Bool {
        WorldTrackingProvider.isSupported
    }

    private let fingerTipUpdates = CurrentValueAsyncStreamRelay(FingerTipsSnapshot.empty)
    private let handSkeletonUpdates = CurrentValueAsyncStreamRelay(HandSkeletonSnapshot.empty)

    @ObservationIgnored private(set) var activeRuntime: Runtime?
    @ObservationIgnored private var desiredRequirements: ARTrackingRequirements = []
    @ObservationIgnored private var authorizationStatusByType: [
        ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus
    ] = [:]

    @ObservationIgnored private var reconcileRequestID = 0
    @ObservationIgnored private var reconcileTask: Task<Void, Never>?
    @ObservationIgnored private var sessionEventsTask: Task<Void, Never>?
    @ObservationIgnored private var handUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var worldAnchorUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var planeAnchorUpdatesTask: Task<Void, Never>?

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot> {
        fingerTipUpdates.makeStream()
    }

    func handSkeletonUpdatesStream() -> AsyncStream<HandSkeletonSnapshot> {
        handSkeletonUpdates.makeStream()
    }

    func deviceWorldTransform(atTimestamp timestamp: TimeInterval) -> simd_float4x4? {
        guard providerStateByName[ProviderKind.world.rawValue] == .running,
              let anchor = activeRuntime?.worldTrackingProvider.queryDeviceAnchor(atTimestamp: timestamp),
              anchor.isTracked else { return nil }
        return anchor.originFromAnchorTransform
    }

    func addWorldAnchor(originFromAnchorTransform: simd_float4x4) async throws -> UUID {
        guard providerStateByName[ProviderKind.world.rawValue] == .running, let activeRuntime else {
            throw ARTrackingServiceError.worldTrackingNotRunning
        }
        let anchor = WorldAnchor(originFromAnchorTransform: originFromAnchorTransform)
        try await activeRuntime.worldTrackingProvider.addAnchor(anchor)
        return anchor.id
    }

    func removeWorldAnchor(id: UUID) async throws {
        guard providerStateByName[ProviderKind.world.rawValue] == .running, let activeRuntime else {
            throw ARTrackingServiceError.worldTrackingNotRunning
        }
        try await activeRuntime.worldTrackingProvider.removeAnchor(forID: id)
    }

    func start(requirements: ARTrackingRequirements) {
        guard requirements.isEmpty == false else {
            stop()
            return
        }

        if requirements == desiredRequirements,
           reconcileTask == nil,
           let activeRuntime,
           providersAreHealthy(runtime: activeRuntime, requirements: requirements)
        {
            return
        }

        desiredRequirements = requirements
        ensureRuntime()
        reconcileRequestID += 1
        scheduleReconcileIfNeeded()
    }

    func stop() {
        desiredRequirements = []
        reconcileRequestID += 1
        tearDownActiveRuntime()
        clearAllTrackingState()
        authorizationStatusByType.removeAll(keepingCapacity: false)

        for kind in [ProviderKind.hand, .world, .plane] {
            switch providerStateByName[kind.rawValue] {
            case .disabled, .unsupported:
                break
            default:
                providerStateByName[kind.rawValue] = .stopped
            }
        }
    }

    private func ensureRuntime() {
        guard activeRuntime == nil else { return }

        let runtime = Runtime()
        activeRuntime = runtime
        worldTrackingGeneration += 1
        providerStateByName[ProviderKind.world.rawValue] =
            WorldTrackingProvider.isSupported ? .idle : .unsupported
        providerStateByName[ProviderKind.hand.rawValue] =
            desiredRequirements.contains(.hand)
                ? (HandTrackingProvider.isSupported ? .idle : .unsupported)
                : .disabled
        providerStateByName[ProviderKind.plane.rawValue] =
            desiredRequirements.contains(.horizontalPlanes)
                ? (PlaneDetectionProvider.isSupported ? .idle : .unsupported)
                : .disabled

        startSessionEvents(runtime: runtime)
        startWorldAnchorUpdates(runtime: runtime)
    }

    private func scheduleReconcileIfNeeded() {
        guard reconcileTask == nil, let runtime = activeRuntime else { return }

        reconcileTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while Task.isCancelled == false, activeRuntime === runtime {
                let requestID = reconcileRequestID
                let requirements = desiredRequirements
                await reconcile(runtime: runtime, requirements: requirements, requestID: requestID)

                guard activeRuntime === runtime else { break }
                guard requestID != reconcileRequestID else { break }
            }
            if activeRuntime === runtime {
                reconcileTask = nil
            }
        }
    }

    private func reconcile(
        runtime: Runtime,
        requirements: ARTrackingRequirements,
        requestID: Int
    ) async {
        guard activeRuntime === runtime else { return }

        prepareOptionalProviders(runtime: runtime, requirements: requirements)
        publishStaticAvailability(runtime: runtime, requirements: requirements)

        let requiredAuthorizations = deduplicatedRequiredAuthorizations(
            runtime: runtime,
            requirements: requirements
        )
        await resolveAuthorizationStatuses(
            requiredAuthorizations,
            runtime: runtime,
            requestID: requestID
        )

        guard activeRuntime === runtime else { return }
        guard requestID == reconcileRequestID else { return }

        publishAuthorizationAvailability(runtime: runtime, requirements: requirements)

        let providers = runnableProviders(runtime: runtime, requirements: requirements)
        guard providers.isEmpty == false else {
            cleanUpDisabledOptionalProviders(runtime: runtime, requirements: requirements)
            return
        }

        do {
            try await runtime.session.run(providers)
        } catch {
            guard activeRuntime === runtime else { return }
            guard requestID == reconcileRequestID else { return }
            invalidateRuntimeAfterRunFailure(
                reason: error.localizedDescription,
                runtime: runtime,
                requirements: requirements
            )
            return
        }

        guard activeRuntime === runtime else { return }
        guard requestID == reconcileRequestID else { return }

        publishCurrentProviderStates(runtime: runtime, requirements: requirements)
        startOptionalUpdateTasks(runtime: runtime, requirements: requirements)
        cleanUpDisabledOptionalProviders(runtime: runtime, requirements: requirements)
    }

    private func prepareOptionalProviders(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        if requirements.contains(.hand), HandTrackingProvider.isSupported {
            if runtime.handTrackingProvider == nil
                || runtime.handTrackingProvider?.state == .stopped
            {
                handUpdatesTask?.cancel()
                handUpdatesTask = nil
                runtime.handTrackingProvider = HandTrackingProvider()
                providerStateByName[ProviderKind.hand.rawValue] = .idle
            }
        }

        if requirements.contains(.horizontalPlanes), PlaneDetectionProvider.isSupported {
            if runtime.planeDetectionProvider == nil
                || runtime.planeDetectionProvider?.state == .stopped
            {
                planeAnchorUpdatesTask?.cancel()
                planeAnchorUpdatesTask = nil
                runtime.planeDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal])
                providerStateByName[ProviderKind.plane.rawValue] = .idle
            }
        }
    }

    private func publishStaticAvailability(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        if WorldTrackingProvider.isSupported == false {
            providerStateByName[ProviderKind.world.rawValue] = .unsupported
        }

        if requirements.contains(.hand) == false {
            providerStateByName[ProviderKind.hand.rawValue] = .disabled
            clearHandTrackingState()
        } else if HandTrackingProvider.isSupported == false {
            providerStateByName[ProviderKind.hand.rawValue] = .unsupported
            clearHandTrackingState()
        } else if let handTrackingProvider = runtime.handTrackingProvider {
            publishProviderState(handTrackingProvider.state, provider: handTrackingProvider, runtime: runtime)
        }

        if requirements.contains(.horizontalPlanes) == false {
            providerStateByName[ProviderKind.plane.rawValue] = .disabled
            clearPlaneTrackingState()
        } else if PlaneDetectionProvider.isSupported == false {
            providerStateByName[ProviderKind.plane.rawValue] = .unsupported
            clearPlaneTrackingState()
        } else if let planeDetectionProvider = runtime.planeDetectionProvider {
            publishProviderState(planeDetectionProvider.state, provider: planeDetectionProvider, runtime: runtime)
        }
    }

    private func resolveAuthorizationStatuses(
        _ types: [ARKitSession.AuthorizationType],
        runtime: Runtime,
        requestID: Int
    ) async {
        let unresolved = types.filter { authorizationStatusByType[$0] == nil }
        guard unresolved.isEmpty == false else { return }

        let queried = await runtime.session.queryAuthorization(for: unresolved)
        guard activeRuntime === runtime else { return }
        for (type, status) in queried {
            authorizationStatusByType[type] = status
        }

        guard requestID == reconcileRequestID else { return }
        let notDetermined = unresolved.filter {
            authorizationStatusByType[$0] == .notDetermined
        }
        guard notDetermined.isEmpty == false else { return }

        let requested = await runtime.session.requestAuthorization(for: notDetermined)
        guard activeRuntime === runtime else { return }
        for (type, status) in requested {
            authorizationStatusByType[type] = status
        }
    }

    private func publishAuthorizationAvailability(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        if requirements.contains(.world),
           WorldTrackingProvider.isSupported,
           isAuthorized(WorldTrackingProvider.requiredAuthorizations) == false
        {
            providerStateByName[ProviderKind.world.rawValue] = .unauthorized
        }

        if requirements.contains(.hand),
           HandTrackingProvider.isSupported,
           runtime.handTrackingProvider != nil,
           isAuthorized(HandTrackingProvider.requiredAuthorizations) == false
        {
            providerStateByName[ProviderKind.hand.rawValue] = .unauthorized
            clearHandTrackingState()
        }

        if requirements.contains(.horizontalPlanes),
           PlaneDetectionProvider.isSupported,
           runtime.planeDetectionProvider != nil,
           isAuthorized(PlaneDetectionProvider.requiredAuthorizations) == false
        {
            providerStateByName[ProviderKind.plane.rawValue] = .unauthorized
            clearPlaneTrackingState()
        }
    }

    private func runnableProviders(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) -> [any DataProvider] {
        var providers: [any DataProvider] = []

        if requirements.contains(.world),
           WorldTrackingProvider.isSupported,
           isAuthorized(WorldTrackingProvider.requiredAuthorizations)
        {
            providers.append(runtime.worldTrackingProvider)
        }

        if requirements.contains(.hand),
           HandTrackingProvider.isSupported,
           isAuthorized(HandTrackingProvider.requiredAuthorizations),
           let handTrackingProvider = runtime.handTrackingProvider
        {
            providers.append(handTrackingProvider)
        }

        if requirements.contains(.horizontalPlanes),
           PlaneDetectionProvider.isSupported,
           isAuthorized(PlaneDetectionProvider.requiredAuthorizations),
           let planeDetectionProvider = runtime.planeDetectionProvider
        {
            providers.append(planeDetectionProvider)
        }

        return providers
    }

    private func invalidateRuntimeAfterRunFailure(
        reason: String,
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        guard activeRuntime === runtime else { return }

        tearDownActiveRuntime()
        clearAllTrackingState()

        if requirements.contains(.world), WorldTrackingProvider.isSupported {
            providerStateByName[ProviderKind.world.rawValue] = .failed(reason: reason)
        }
        if requirements.contains(.hand), HandTrackingProvider.isSupported {
            providerStateByName[ProviderKind.hand.rawValue] = .failed(reason: reason)
        }
        if requirements.contains(.horizontalPlanes), PlaneDetectionProvider.isSupported {
            providerStateByName[ProviderKind.plane.rawValue] = .failed(reason: reason)
        }
    }

    private func startSessionEvents(runtime: Runtime) {
        sessionEventsTask?.cancel()
        sessionEventsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in runtime.session.events {
                guard Task.isCancelled == false, activeRuntime === runtime else { return }
                switch event {
                case let .authorizationChanged(type, status):
                    authorizationStatusByType[type] = status
                    handleAuthorizationChange(type: type, status: status, runtime: runtime)

                case let .dataProviderStateChanged(dataProviders, newState, error):
                    for provider in dataProviders {
                        publishProviderState(
                            newState,
                            errorDescription: error?.localizedDescription,
                            provider: provider,
                            runtime: runtime
                        )
                    }

                @unknown default:
                    break
                }
            }
        }
    }

    private func handleAuthorizationChange(
        type: ARKitSession.AuthorizationType,
        status: ARKitSession.AuthorizationStatus,
        runtime: Runtime
    ) {
        guard activeRuntime === runtime else { return }

        let authorizationState = Self.trackingState(for: status)

        if WorldTrackingProvider.requiredAuthorizations.contains(type),
           desiredRequirements.contains(.world),
           let authorizationState
        {
            providerStateByName[ProviderKind.world.rawValue] = authorizationState
        }

        if HandTrackingProvider.requiredAuthorizations.contains(type),
           desiredRequirements.contains(.hand),
           let authorizationState
        {
            providerStateByName[ProviderKind.hand.rawValue] = authorizationState
            clearHandTrackingState()
        }

        if PlaneDetectionProvider.requiredAuthorizations.contains(type),
           desiredRequirements.contains(.horizontalPlanes),
           let authorizationState
        {
            providerStateByName[ProviderKind.plane.rawValue] = authorizationState
            clearPlaneTrackingState()
        }

        if status == .allowed {
            reconcileRequestID += 1
            scheduleReconcileIfNeeded()
        }
    }

    private func publishCurrentProviderStates(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        if requirements.contains(.world) {
            publishProviderState(
                runtime.worldTrackingProvider.state,
                provider: runtime.worldTrackingProvider,
                runtime: runtime
            )
        }
        if requirements.contains(.hand), let provider = runtime.handTrackingProvider {
            publishProviderState(provider.state, provider: provider, runtime: runtime)
        }
        if requirements.contains(.horizontalPlanes), let provider = runtime.planeDetectionProvider {
            publishProviderState(provider.state, provider: provider, runtime: runtime)
        }
    }

    private func publishProviderState(
        _ state: DataProviderState,
        errorDescription: String? = nil,
        provider: any DataProvider,
        runtime: Runtime
    ) {
        guard activeRuntime === runtime else { return }
        guard let kind = providerKind(for: provider, runtime: runtime) else { return }

        let isDesired = desiredRequirements.contains(kind.requirement)
        let mappedState: ARTrackingProviderState

        if isDesired == false {
            mappedState = .disabled
        } else if let errorDescription {
            mappedState = .failed(reason: errorDescription)
        } else {
            mappedState = Self.trackingState(for: state)
        }

        providerStateByName[kind.rawValue] = mappedState

        switch kind {
        case .hand:
            if mappedState != .running {
                clearHandTrackingState()
            }
        case .plane:
            if mappedState == .running {
                rebuildDetectedPlanes()
            } else {
                detectedPlanes.removeAll(keepingCapacity: false)
                if mappedState != .paused {
                    planeAnchorsByID.removeAll(keepingCapacity: false)
                }
            }
        case .world:
            if isDesired && (state == .stopped || errorDescription != nil) {
                invalidateRuntimeAfterWorldFailure(runtime)
            }
        }
    }

    static func trackingState(for state: DataProviderState) -> ARTrackingProviderState {
        switch state {
        case .initialized: .idle
        case .running: .running
        case .paused: .paused
        case .stopped: .stopped
        @unknown default: .stopped
        }
    }

    static func trackingState(
        for status: ARKitSession.AuthorizationStatus
    ) -> ARTrackingProviderState? {
        switch status {
        case .allowed:
            nil
        case .notDetermined, .denied:
            .unauthorized
        @unknown default:
            .unauthorized
        }
    }

    private func providerKind(
        for provider: any DataProvider,
        runtime: Runtime
    ) -> ProviderKind? {
        let identity = ObjectIdentifier(provider)
        if identity == ObjectIdentifier(runtime.worldTrackingProvider) {
            return .world
        }
        if let handTrackingProvider = runtime.handTrackingProvider,
           identity == ObjectIdentifier(handTrackingProvider)
        {
            return .hand
        }
        if let planeDetectionProvider = runtime.planeDetectionProvider,
           identity == ObjectIdentifier(planeDetectionProvider)
        {
            return .plane
        }
        return nil
    }

    private func startWorldAnchorUpdates(runtime: Runtime) {
        worldAnchorUpdatesTask?.cancel()
        worldAnchorUpdatesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await update in runtime.worldTrackingProvider.anchorUpdates {
                guard Task.isCancelled == false, activeRuntime === runtime else { return }
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

    private func startOptionalUpdateTasks(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        if requirements.contains(.hand),
           handUpdatesTask == nil,
           let handTrackingProvider = runtime.handTrackingProvider
        {
            handUpdatesTask = Task { @MainActor [weak self, weak handTrackingProvider] in
                guard let self, let handTrackingProvider else { return }
                for await update in handTrackingProvider.anchorUpdates {
                    guard Task.isCancelled == false,
                          activeRuntime === runtime,
                          runtime.handTrackingProvider === handTrackingProvider else { return }
                    updateHandTracking(from: update.anchor)
                }
            }
        }

        if requirements.contains(.horizontalPlanes),
           planeAnchorUpdatesTask == nil,
           let planeDetectionProvider = runtime.planeDetectionProvider
        {
            planeAnchorUpdatesTask = Task { @MainActor [weak self, weak planeDetectionProvider] in
                guard let self, let planeDetectionProvider else { return }
                for await update in planeDetectionProvider.anchorUpdates {
                    guard Task.isCancelled == false,
                          activeRuntime === runtime,
                          runtime.planeDetectionProvider === planeDetectionProvider else { return }
                    switch update.event {
                    case .removed:
                        planeAnchorsByID.removeValue(forKey: update.anchor.id)
                    case .added, .updated:
                        planeAnchorsByID[update.anchor.id] = update.anchor
                    @unknown default:
                        planeAnchorsByID[update.anchor.id] = update.anchor
                    }
                    if providerStateByName[ProviderKind.plane.rawValue] == .running {
                        rebuildDetectedPlanes()
                    }
                }
            }
        }
    }

    private func cleanUpDisabledOptionalProviders(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) {
        if requirements.contains(.hand) == false {
            handUpdatesTask?.cancel()
            handUpdatesTask = nil
            runtime.handTrackingProvider = nil
            clearHandTrackingState()
            providerStateByName[ProviderKind.hand.rawValue] = .disabled
        }

        if requirements.contains(.horizontalPlanes) == false {
            planeAnchorUpdatesTask?.cancel()
            planeAnchorUpdatesTask = nil
            runtime.planeDetectionProvider = nil
            clearPlaneTrackingState()
            providerStateByName[ProviderKind.plane.rawValue] = .disabled
        }
    }

    private func providersAreHealthy(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) -> Bool {
        if requirements.contains(.world),
           providerStateByName[ProviderKind.world.rawValue] != .running
        {
            return false
        }

        if requirements.contains(.hand),
           providerStateByName[ProviderKind.hand.rawValue] != .running
        {
            return false
        }

        if requirements.contains(.horizontalPlanes),
           providerStateByName[ProviderKind.plane.rawValue] != .running
        {
            return false
        }

        return activeRuntime === runtime
    }

    private func invalidateRuntimeAfterWorldFailure(_ runtime: Runtime) {
        guard activeRuntime === runtime else { return }

        let worldState = providerStateByName[ProviderKind.world.rawValue] ?? .stopped
        tearDownActiveRuntime()
        clearAllTrackingState()
        providerStateByName[ProviderKind.world.rawValue] = worldState
        if desiredRequirements.contains(.hand) {
            providerStateByName[ProviderKind.hand.rawValue] = .stopped
        }
        if desiredRequirements.contains(.horizontalPlanes) {
            providerStateByName[ProviderKind.plane.rawValue] = .stopped
        }
    }

    private func tearDownActiveRuntime() {
        reconcileTask?.cancel()
        reconcileTask = nil
        sessionEventsTask?.cancel()
        sessionEventsTask = nil
        handUpdatesTask?.cancel()
        handUpdatesTask = nil
        worldAnchorUpdatesTask?.cancel()
        worldAnchorUpdatesTask = nil
        planeAnchorUpdatesTask?.cancel()
        planeAnchorUpdatesTask = nil

        activeRuntime?.session.stop()
        activeRuntime = nil
    }

    private func clearAllTrackingState() {
        clearHandTrackingState()
        worldAnchorsByID.removeAll(keepingCapacity: false)
        clearPlaneTrackingState()
    }

    private func clearHandTrackingState() {
        fingerTipsSnapshot = .empty
        fingerTipUpdates.yield(.empty)
        handSkeletonSnapshot = .empty
        handSkeletonUpdates.yield(.empty)
    }

    private func clearPlaneTrackingState() {
        planeAnchorsByID.removeAll(keepingCapacity: false)
        detectedPlanes.removeAll(keepingCapacity: false)
    }

    private func deduplicatedRequiredAuthorizations(
        runtime: Runtime,
        requirements: ARTrackingRequirements
    ) -> [ARKitSession.AuthorizationType] {
        var seen: Set<ARKitSession.AuthorizationType> = []
        var ordered: [ARKitSession.AuthorizationType] = []
        var required: [ARKitSession.AuthorizationType] = []

        if requirements.contains(.world), WorldTrackingProvider.isSupported {
            required += WorldTrackingProvider.requiredAuthorizations
        }
        if requirements.contains(.hand),
           HandTrackingProvider.isSupported,
           runtime.handTrackingProvider != nil
        {
            required += HandTrackingProvider.requiredAuthorizations
        }
        if requirements.contains(.horizontalPlanes),
           PlaneDetectionProvider.isSupported,
           runtime.planeDetectionProvider != nil
        {
            required += PlaneDetectionProvider.requiredAuthorizations
        }

        for type in required where seen.insert(type).inserted {
            ordered.append(type)
        }
        return ordered
    }

    private func isAuthorized(
        _ requiredAuthorizations: [ARKitSession.AuthorizationType]
    ) -> Bool {
        requiredAuthorizations.allSatisfy { authorizationStatusByType[$0] == .allowed }
    }

    private func updateHandTracking(from anchor: HandAnchor) {
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
        handSkeletonSnapshot[side] = extractHandSkeleton(from: anchor)
        handSkeletonUpdates.yield(handSkeletonSnapshot)
    }

    private func extractHandSkeleton(from anchor: HandAnchor) -> TrackedHandSkeleton {
        guard anchor.isTracked, let handSkeleton = anchor.handSkeleton else {
            return TrackedHandSkeleton()
        }

        var joints: [TrackedHandJoint: SIMD3<Float>] = [:]
        joints.reserveCapacity(TrackedHandJoint.allCases.count)
        for jointName in TrackedHandJoint.allCases {
            let joint = handSkeleton.joint(jointName.arkitName)
            guard joint.isTracked else { continue }
            let transform = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            joints[jointName] = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }
        return TrackedHandSkeleton(isTracked: true, joints: joints)
    }

    private func rebuildDetectedPlanes() {
        detectedPlanes = planeAnchorsByID.values.map { anchor in
            DetectedPlane(id: anchor.id, worldFromPlane: anchor.originFromAnchorTransform)
        }
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

private extension TrackedHandJoint {
    var arkitName: HandSkeleton.JointName {
        switch self {
        case .forearmArm: .forearmArm
        case .forearmWrist: .forearmWrist
        case .wrist: .wrist
        case .thumbKnuckle: .thumbKnuckle
        case .thumbIntermediateBase: .thumbIntermediateBase
        case .thumbIntermediateTip: .thumbIntermediateTip
        case .thumbTip: .thumbTip
        case .indexFingerMetacarpal: .indexFingerMetacarpal
        case .indexFingerKnuckle: .indexFingerKnuckle
        case .indexFingerIntermediateBase: .indexFingerIntermediateBase
        case .indexFingerIntermediateTip: .indexFingerIntermediateTip
        case .indexFingerTip: .indexFingerTip
        case .middleFingerMetacarpal: .middleFingerMetacarpal
        case .middleFingerKnuckle: .middleFingerKnuckle
        case .middleFingerIntermediateBase: .middleFingerIntermediateBase
        case .middleFingerIntermediateTip: .middleFingerIntermediateTip
        case .middleFingerTip: .middleFingerTip
        case .ringFingerMetacarpal: .ringFingerMetacarpal
        case .ringFingerKnuckle: .ringFingerKnuckle
        case .ringFingerIntermediateBase: .ringFingerIntermediateBase
        case .ringFingerIntermediateTip: .ringFingerIntermediateTip
        case .ringFingerTip: .ringFingerTip
        case .littleFingerMetacarpal: .littleFingerMetacarpal
        case .littleFingerKnuckle: .littleFingerKnuckle
        case .littleFingerIntermediateBase: .littleFingerIntermediateBase
        case .littleFingerIntermediateTip: .littleFingerIntermediateTip
        case .littleFingerTip: .littleFingerTip
        }
    }
}
