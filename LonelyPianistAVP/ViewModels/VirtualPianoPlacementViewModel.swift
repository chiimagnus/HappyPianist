import Foundation
import simd

@MainActor
@Observable
final class VirtualPianoPlacementViewModel {
    enum PlacementState: Equatable {
        case disabled
        case placing(reticlePoint: SIMD3<Float>, isReadyToConfirm: Bool)
        case placed(worldFromKeyboard: simd_float4x4, scale: Float)
    }

    private static let whiteKeyWidthMeters: Float = 0.0235
    private static let whiteKeySpacingMeters: Float = whiteKeyWidthMeters / 0.95
    private static let totalKeyboardLengthMeters: Float = whiteKeySpacingMeters * Float(52 - 1)
    private static let pressThresholdMeters: Float = 0.018

    private(set) var state: PlacementState = .disabled
    private var wasPinching = false

    var isPlaced: Bool {
        if case .placed = state { return true }
        return false
    }

    var worldFromKeyboard: simd_float4x4? {
        if case let .placed(transform, _) = state { return transform }
        return nil
    }

    func reset() {
        state = .disabled
        wasPinching = false
    }

    func startPlacing() {
        state = .placing(reticlePoint: .zero, isReadyToConfirm: false)
    }

    func update(
        fingerTips: [String: SIMD3<Float>],
        nowUptime _: TimeInterval
    ) {
        guard case .placing = state else { return }

        guard let reticlePoint = fingerTips["right_indexFinger_tip"] ?? fingerTips["left_indexFinger_tip"] else {
            return
        }

        let isReady = true

        let isPinching = checkPinch(fingerTips: fingerTips)
        let shouldConfirm = isPinching && wasPinching == false
        wasPinching = isPinching

        if shouldConfirm, isReady {
            confirmPlacement(at: reticlePoint)
        } else {
            state = .placing(reticlePoint: reticlePoint, isReadyToConfirm: isReady)
        }
    }

    private func checkPinch(fingerTips: [String: SIMD3<Float>]) -> Bool {
        guard
            let index = fingerTips["right_indexFinger_tip"],
            let thumb = fingerTips["right_thumb_tip"]
        else {
            return false
        }
        return simd_length(index - thumb) < Self.pressThresholdMeters
    }

    private func confirmPlacement(at reticlePoint: SIMD3<Float>) {
        let xAxisWorld = SIMD3<Float>(1, 0, 0)
        let yAxisWorld = SIMD3<Float>(0, 1, 0)
        let zAxis = simd_normalize(simd_cross(xAxisWorld, yAxisWorld))
        let xAxis = simd_normalize(simd_cross(yAxisWorld, zAxis))

        let originWorld = reticlePoint - xAxis * (Self.totalKeyboardLengthMeters / 2)

        let transform = simd_float4x4(columns: (
            SIMD4<Float>(xAxis, 0),
            SIMD4<Float>(yAxisWorld, 0),
            SIMD4<Float>(zAxis, 0),
            SIMD4<Float>(originWorld, 1)
        ))

        state = .placed(worldFromKeyboard: transform, scale: 1.0)
    }
}
