import ARKit
import Foundation
import simd

@MainActor
protocol ARTrackingServiceProtocol: AnyObject {
    var fingerTipPositions: [String: SIMD3<Float>] { get }
    var leftIndexFingerTipPosition: SIMD3<Float>? { get }
    var leftThumbTipPosition: SIMD3<Float>? { get }
    var rightIndexFingerTipPosition: SIMD3<Float>? { get }
    var rightThumbTipPosition: SIMD3<Float>? { get }
    var worldAnchorsByID: [UUID: WorldAnchor] { get }
    var planeAnchorsByID: [UUID: PlaneAnchor] { get }
    var authorizationStatusByType: [ARKitSession.AuthorizationType: ARKitSession.AuthorizationStatus] { get }
    var providerStateByName: [String: DataProviderState] { get }
    var isWorldTrackingSupported: Bool { get }
    var worldTrackingProvider: WorldTrackingProvider { get }

    func fingerTipUpdatesStream() -> AsyncStream<[String: SIMD3<Float>]>
    func start(mode: ARTrackingMode)
    func stop()
}
