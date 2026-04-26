import ARKit
import Foundation
import Observation
import simd

@MainActor
protocol ARTrackingServiceProtocol: AnyObject {
    var fingerTipPositions: [String: SIMD3<Float>] { get }
    var leftIndexFingerTipPosition: SIMD3<Float>? { get }
    var leftThumbTipPosition: SIMD3<Float>? { get }
    var rightIndexFingerTipPosition: SIMD3<Float>? { get }
    var rightThumbTipPosition: SIMD3<Float>? { get }
    var worldAnchorsByID: [UUID: WorldAnchor] { get }
    var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] { get }
    var providerStateByName: [String: DataProviderState] { get }
    var isWorldTrackingSupported: Bool { get }
    var worldTrackingProvider: WorldTrackingProvider { get }

    func fingerTipUpdatesStream() -> AsyncStream<[String: SIMD3<Float>]>
    func start()
    func stop()
}

enum DataProviderState: Equatable {
    case idle
    case running
    case unsupported
    case unauthorized
    case stopped
    case failed(reason: String)

    var description: String {
        switch self {
            case .idle:
                "idle"
            case .running:
                "running"
            case .unsupported:
                "unsupported"
            case .unauthorized:
                "unauthorized"
            case .stopped:
                "stopped"
            case let .failed(reason):
                "failed(\(reason))"
        }
    }
}

@MainActor
@Observable
final class ARTrackingService: ARTrackingServiceProtocol {
    private(set) var fingerTipPositions: [String: SIMD3<Float>] = [:]
    private(set) var leftIndexFingerTipPosition: SIMD3<Float>?
    private(set) var leftThumbTipPosition: SIMD3<Float>?
    private(set) var rightIndexFingerTipPosition: SIMD3<Float>?
    private(set) var rightThumbTipPosition: SIMD3<Float>?
    private(set) var worldAnchorsByID: [UUID: WorldAnchor] = [:]
    private(set) var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] = [:]
    private(set) var providerStateByName: [String: DataProviderState] = [
        "hand": .idle,
        "world": .idle,
    ]

    var isWorldTrackingSupported: Bool {
        WorldTrackingProvider.isSupported
    }

    let worldTrackingProvider = WorldTrackingProvider()

    private let session = ARKitSession()
    private let handTrackingProvider = HandTrackingProvider()

    private var sessionTask: Task<Void, Never>?
    private var handUpdatesTask: Task<Void, Never>?
    private var worldAnchorUpdatesTask: Task<Void, Never>?

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

    func start() {
        guard sessionTask == nil else { return }

        let isHandSupported = HandTrackingProvider.isSupported
        let isWorldSupported = WorldTrackingProvider.isSupported

        if isHandSupported == false {
            providerStateByName["hand"] = .unsupported
        }
        if isWorldSupported == false {
            providerStateByName["world"] = .unsupported
        }

        guard isHandSupported || isWorldSupported else { return }

        sessionTask = Task { [weak self] in
            guard let self else { return }

            let handRequiredAuthorizations = isHandSupported ? HandTrackingProvider.requiredAuthorizations : []
            let worldRequiredAuthorizations = isWorldSupported ? WorldTrackingProvider.requiredAuthorizations : []

            let requiredAuthorizations = deduplicatedRequiredAuthorizations(
                includeHand: isHandSupported,
                includeWorld: isWorldSupported
            )
            let statuses: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] =
                requiredAuthorizations.isEmpty ? [:] : await session.requestAuthorization(for: requiredAuthorizations)
            authorizationStatusByType = statuses

            let isHandAllowed = isHandSupported && isAuthorized(
                requiredAuthorizations: handRequiredAuthorizations,
                statuses: statuses
            )
            let isWorldAllowed = isWorldSupported && isAuthorized(
                requiredAuthorizations: worldRequiredAuthorizations,
                statuses: statuses
            )

            if isHandSupported, isHandAllowed == false {
                providerStateByName["hand"] = .unauthorized
            }
            if isWorldSupported, isWorldAllowed == false {
                providerStateByName["world"] = .unauthorized
            }

            var providersToRun: [any DataProvider] = []
            if isHandAllowed {
                providersToRun.append(handTrackingProvider)
            }
            if isWorldAllowed {
                providersToRun.append(worldTrackingProvider)
            }

            guard providersToRun.isEmpty == false else {
                sessionTask = nil
                return
            }

            do {
                try await session.run(providersToRun)
                if isHandAllowed { providerStateByName["hand"] = .running }
                if isWorldAllowed { providerStateByName["world"] = .running }
                startUpdateTasks()
            } catch {
                if error is CancellationError {
                    if case .running = providerStateByName["hand"] {
                        providerStateByName["hand"] = .stopped
                    }
                    if case .running = providerStateByName["world"] {
                        providerStateByName["world"] = .stopped
                    }
                } else {
                    if isHandAllowed { providerStateByName["hand"] = .failed(reason: error.localizedDescription) }
                    if isWorldAllowed { providerStateByName["world"] = .failed(reason: error.localizedDescription) }
                }
            }

            sessionTask = nil
        }
    }

    func stop() {
        handUpdatesTask?.cancel()
        worldAnchorUpdatesTask?.cancel()
        sessionTask?.cancel()

        handUpdatesTask = nil
        worldAnchorUpdatesTask = nil
        sessionTask = nil

        fingerTipUpdatesContinuation?.finish()
        fingerTipUpdatesContinuation = nil

        fingerTipPositions.removeAll()
        leftIndexFingerTipPosition = nil
        rightIndexFingerTipPosition = nil
        rightThumbTipPosition = nil
        worldAnchorsByID.removeAll()

        if case .running = providerStateByName["hand"] {
            providerStateByName["hand"] = .stopped
        }
        if case .running = providerStateByName["world"] {
            providerStateByName["world"] = .stopped
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
    }

    private func deduplicatedRequiredAuthorizations(
        includeHand: Bool,
        includeWorld: Bool
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
        for jointName in jointNames {
            let joint = handSkeleton.joint(jointName)
            guard joint.isTracked else { continue }
            let worldTransform = anchor.originFromAnchorTransform * joint.anchorFromJointTransform
            let point = SIMD3<Float>(
                worldTransform.columns.3.x,
                worldTransform.columns.3.y,
                worldTransform.columns.3.z
            )
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
        return (tips, indexFingerTip, thumbTip)
    }
}
