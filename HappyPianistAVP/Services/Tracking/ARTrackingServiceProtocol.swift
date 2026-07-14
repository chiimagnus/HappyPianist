import ARKit
import Foundation
import simd

@MainActor
protocol ARTrackingServiceProtocol: AnyObject {
    var fingerTipsSnapshot: FingerTipsSnapshot { get }
    var worldAnchorsByID: [UUID: WorldAnchor] { get }
    var planeAnchorsByID: [UUID: PlaneAnchor] { get }
    var detectedPlanes: [DetectedPlane] { get }
    var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] { get }
    var providerStateByName: [String: DataProviderState] { get }
    var activeRequirements: ARTrackingRequirements { get }
    var isWorldTrackingSupported: Bool { get }

    func fingerTipUpdatesStream() -> AsyncStream<FingerTipsSnapshot>
    func deviceWorldTransform(atTimestamp timestamp: TimeInterval) -> simd_float4x4?
    func addWorldAnchor(originFromAnchorTransform: simd_float4x4) async throws -> UUID
    func removeWorldAnchor(id: UUID) async throws
    func start(requirements: ARTrackingRequirements)
    func stop()
}
