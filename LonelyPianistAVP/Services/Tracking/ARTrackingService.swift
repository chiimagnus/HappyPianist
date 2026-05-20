import ARKit
import Foundation
import simd

@MainActor
final class ARTrackingService: ARTrackingServiceProtocol {
    private(set) var fingerTipPositions: [String: SIMD3<Float>] = [:]
    private(set) var leftIndexFingerTipPosition: SIMD3<Float>?
    private(set) var leftThumbTipPosition: SIMD3<Float>?
    private(set) var rightIndexFingerTipPosition: SIMD3<Float>?
    private(set) var rightThumbTipPosition: SIMD3<Float>?
    private(set) var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    private(set) var planeAnchorsByID: [UUID: PlaneAnchor] = [:]
    private(set) var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] = [:]
    private(set) var providerStateByName: [String: DataProviderState] = [
        "hand": .idle,
        "world": .idle,
        "plane": .idle,
    ]

    var isWorldTrackingSupported: Bool {
        WorldTrackingProvider.isSupported
    }

    let worldTrackingProvider = WorldTrackingProvider()

    private let session = ARKitSession()
    private let handTrackingProvider = HandTrackingProvider()
    private let planeDetectionProvider = PlaneDetectionProvider(alignments: [.horizontal])

    private var sessionTask: Task<Void, Never>?
    private var handUpdatesTask: Task<Void, Never>?
    private var worldAnchorUpdatesTask: Task<Void, Never>?
    private var planeAnchorUpdatesTask: Task<Void, Never>?

    private var fingerTipUpdatesContinuation: AsyncStream<[String: SIMD3<Float>]>.Continuation?

    func fingerTipUpdatesStream() -> AsyncStream<[String: SIMD3<Float>]> {
        AsyncStream { continuation in
            fingerTipUpdatesContinuation?.finish()
            fingerTipUpdatesContinuation = continuation
            continuation.yield(fingerTipPositions)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.fingerTipUpdatesContinuation = nil
                }
            }
        }
    }

    func start(mode: ARTrackingMode) {
        guard sessionTask == nil else { return }

        let isHandSupported = HandTrackingProvider.isSupported
        let isWorldSupported = WorldTrackingProvider.isSupported
        let isPlaneSupported = PlaneDetectionProvider.isSupported

        let shouldIncludeHand = switch mode {
            case .calibration, .practiceVirtualOrAudio:
                true
            case .practiceBluetoothMIDI:
                false
        }

        if shouldIncludeHand == false {
            providerStateByName["hand"] = .disabled
        } else if isHandSupported == false {
            providerStateByName["hand"] = .unsupported
        }
        if isWorldSupported == false {
            providerStateByName["world"] = .unsupported
        }
        if isPlaneSupported == false {
            providerStateByName["plane"] = .unsupported
        }

        guard (shouldIncludeHand && isHandSupported) || isWorldSupported || isPlaneSupported else { return }

        sessionTask = Task { [weak self] in
            guard let self else { return }

            let handRequiredAuthorizations = (shouldIncludeHand && isHandSupported) ? HandTrackingProvider
                .requiredAuthorizations : []
            let worldRequiredAuthorizations = isWorldSupported ? WorldTrackingProvider.requiredAuthorizations : []
            let planeRequiredAuthorizations = isPlaneSupported ? PlaneDetectionProvider.requiredAuthorizations : []

            let requiredAuthorizations = deduplicatedRequiredAuthorizations(
                includeHand: shouldIncludeHand && isHandSupported,
                includeWorld: isWorldSupported,
                includePlane: isPlaneSupported
            )
            let statuses: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] =
                requiredAuthorizations.isEmpty ? [:] : await session.requestAuthorization(for: requiredAuthorizations)
            authorizationStatusByType = statuses

            let isHandAllowed = shouldIncludeHand && isHandSupported && isAuthorized(
                requiredAuthorizations: handRequiredAuthorizations,
                statuses: statuses
            )
            let isWorldAllowed = isWorldSupported && isAuthorized(
                requiredAuthorizations: worldRequiredAuthorizations,
                statuses: statuses
            )
            let isPlaneAllowed = isPlaneSupported && isAuthorized(
                requiredAuthorizations: planeRequiredAuthorizations,
                statuses: statuses
            )

            if shouldIncludeHand, isHandSupported, isHandAllowed == false {
                providerStateByName["hand"] = .unauthorized
            }
            if isWorldSupported, isWorldAllowed == false {
                providerStateByName["world"] = .unauthorized
            }
            if isPlaneSupported, isPlaneAllowed == false {
                providerStateByName["plane"] = .unauthorized
            }

            var providersToRun: [any DataProvider] = []
            if isHandAllowed {
                providersToRun.append(handTrackingProvider)
            }
            if isWorldAllowed {
                providersToRun.append(worldTrackingProvider)
            }
            if isPlaneAllowed {
                providersToRun.append(planeDetectionProvider)
            }

            guard providersToRun.isEmpty == false else {
                sessionTask = nil
                return
            }

            do {
                try await session.run(providersToRun)
                if isHandAllowed { providerStateByName["hand"] = .running }
                if isWorldAllowed { providerStateByName["world"] = .running }
                if isPlaneAllowed { providerStateByName["plane"] = .running }
                startUpdateTasks()
            } catch {
                if error is CancellationError {
                    if case .running = providerStateByName["hand"] {
                        providerStateByName["hand"] = .stopped
                    }
                    if case .running = providerStateByName["world"] {
                        providerStateByName["world"] = .stopped
                    }
                    if case .running = providerStateByName["plane"] {
                        providerStateByName["plane"] = .stopped
                    }
                } else {
                    if isHandAllowed { providerStateByName["hand"] = .failed(reason: error.localizedDescription) }
                    if isWorldAllowed { providerStateByName["world"] = .failed(reason: error.localizedDescription) }
                    if isPlaneAllowed { providerStateByName["plane"] = .failed(reason: error.localizedDescription) }
                }
            }

            sessionTask = nil
        }
    }

    func stop() {
        handUpdatesTask?.cancel()
        worldAnchorUpdatesTask?.cancel()
        planeAnchorUpdatesTask?.cancel()
        sessionTask?.cancel()

        handUpdatesTask = nil
        worldAnchorUpdatesTask = nil
        planeAnchorUpdatesTask = nil
        sessionTask = nil

        fingerTipUpdatesContinuation?.finish()
        fingerTipUpdatesContinuation = nil

        fingerTipPositions.removeAll()
        leftIndexFingerTipPosition = nil
        rightIndexFingerTipPosition = nil
        rightThumbTipPosition = nil
        worldAnchorsByID.removeAll()
        planeAnchorsByID.removeAll()

        if case .running = providerStateByName["hand"] {
            providerStateByName["hand"] = .stopped
        }
        if case .running = providerStateByName["world"] {
            providerStateByName["world"] = .stopped
        }
        if case .running = providerStateByName["plane"] {
            providerStateByName["plane"] = .stopped
        }
    }

    private func startUpdateTasks() {
        if handUpdatesTask == nil, providerStateByName["hand"] == .running {
            handUpdatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in handTrackingProvider.anchorUpdates {
                    guard Task.isCancelled == false else { return }

                    let chiralityPrefix = "\(update.anchor.chirality)-"
                    guard update.anchor.isTracked else {
                        fingerTipPositions = fingerTipPositions.filter { key, _ in
                            key.hasPrefix(chiralityPrefix) == false
                        }
                        switch update.anchor.chirality {
                            case .left:
                                leftIndexFingerTipPosition = nil
                                leftThumbTipPosition = nil
                            case .right:
                                rightIndexFingerTipPosition = nil
                                rightThumbTipPosition = nil
                            @unknown default:
                                break
                        }
                        fingerTipUpdatesContinuation?.yield(fingerTipPositions)
                        continue
                    }

                    let extracted = extractFingerTips(from: update.anchor)
                    fingerTipPositions = fingerTipPositions.filter { key, _ in
                        key.hasPrefix(chiralityPrefix) == false
                    }
                    fingerTipPositions.merge(extracted.tips, uniquingKeysWith: { _, new in new })

                    switch update.anchor.chirality {
                        case .left:
                            leftIndexFingerTipPosition = extracted.indexFingerTip
                            leftThumbTipPosition = extracted.thumbTip
                        case .right:
                            rightIndexFingerTipPosition = extracted.indexFingerTip
                            rightThumbTipPosition = extracted.thumbTip
                        @unknown default:
                            break
                    }
                    fingerTipUpdatesContinuation?.yield(fingerTipPositions)
                }
            }
        }

        if worldAnchorUpdatesTask == nil, providerStateByName["world"] == .running {
            worldAnchorUpdatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in worldTrackingProvider.anchorUpdates {
                    guard Task.isCancelled == false else { return }
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
                    guard Task.isCancelled == false else { return }
                    switch update.event {
                        case .removed:
                            planeAnchorsByID.removeValue(forKey: update.anchor.id)
                        case .added, .updated:
                            planeAnchorsByID[update.anchor.id] = update.anchor
                        @unknown default:
                            planeAnchorsByID[update.anchor.id] = update.anchor
                    }
                }
            }
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
        if includeHand {
            required += HandTrackingProvider.requiredAuthorizations
        }
        if includeWorld {
            required += WorldTrackingProvider.requiredAuthorizations
        }
        if includePlane {
            required += PlaneDetectionProvider.requiredAuthorizations
        }

        for type in required {
            if seen.insert(type).inserted {
                ordered.append(type)
            }
        }
        return ordered
    }

    private func isAuthorized(
        requiredAuthorizations: [ARKitSession.AuthorizationType],
        statuses: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus]
    ) -> Bool {
        for required in requiredAuthorizations {
            if statuses[required] != .allowed {
                return false
            }
        }
        return true
    }

    private func extractFingerTips(
        from anchor: HandAnchor
    ) -> (tips: [String: SIMD3<Float>], indexFingerTip: SIMD3<Float>?, thumbTip: SIMD3<Float>?) {
        guard let handSkeleton = anchor.handSkeleton else { return ([:], nil, nil) }
        let jointNames: [HandSkeleton.JointName] = [
            .thumbTip,
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip,
        ]

        var tips: [String: SIMD3<Float>] = [:]
        var indexFingerTip: SIMD3<Float>?
        var thumbTip: SIMD3<Float>?
        var palmCandidates: [SIMD3<Float>] = []

        func recordIfTracked(_ jointName: HandSkeleton.JointName) -> SIMD3<Float>? {
            let joint = handSkeleton.joint(jointName)
            guard joint.isTracked else { return nil }
            let worldTransform = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            return SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
        }

        for jointName in jointNames {
            guard let point = recordIfTracked(jointName) else { continue }
            tips["\(anchor.chirality)-\(jointName)"] = point
            switch jointName {
                case .indexFingerTip:
                    indexFingerTip = point
                case .thumbTip:
                    thumbTip = point
                default:
                    break
            }
        }

        // 更稳定的“掌心中心点”用于放置确认：比 fingertip 更不易丢失且抖动更小。
        // 说明：ARKit hand skeleton 没有显式 palm joint，这里用 wrist + 各指 metacarpal/knuckle 近似。
        let palmJointNames: [HandSkeleton.JointName] = [
            .wrist,
            .thumbKnuckle,
            .indexFingerMetacarpal,
            .middleFingerMetacarpal,
            .ringFingerMetacarpal,
            .littleFingerMetacarpal,
        ]
        for jointName in palmJointNames {
            if let point = recordIfTracked(jointName) {
                palmCandidates.append(point)
            }
        }
        if palmCandidates.isEmpty == false {
            let center = palmCandidates.reduce(SIMD3<Float>(0, 0, 0), +) / Float(palmCandidates.count)
            tips["\(anchor.chirality)-palmCenter"] = center
        }
        return (tips, indexFingerTip, thumbTip)
    }
}
