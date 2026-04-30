import Foundation
import simd

@MainActor
@Observable
final class VirtualPianoPlacementViewModel {
    enum PlacementState: Equatable {
        case disabled
        case placing(reticlePoint: SIMD3<Float>?)
        case placed(worldFromKeyboard: simd_float4x4)
    }

    private static let totalKeyboardLengthMeters: Float = VirtualPianoKeyGeometryService.totalKeyboardLengthMeters
    private static let pressThresholdMeters: Float = 0.018

    private(set) var state: PlacementState = .disabled
    private var wasPinching = false

    var isPlaced: Bool {
        if case .placed = state { return true }
        return false
    }

    var worldFromKeyboard: simd_float4x4? {
        if case let .placed(transform) = state { return transform }
        return nil
    }

    func reset() {
        state = .disabled
        wasPinching = false
    }

    func startPlacing() {
        state = .placing(reticlePoint: nil)
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Simulator 自动放置：以默认位置直接进入 placed 状态，跳过手势放置。
    func placeAtDefaultPosition() {
        let xAxisWorld = SIMD3<Float>(1, 0, 0)
        let yAxisWorld = SIMD3<Float>(0, 1, 0)
        let zAxis = simd_normalize(simd_cross(xAxisWorld, yAxisWorld))
        let xAxis = simd_normalize(simd_cross(yAxisWorld, zAxis))

        // 默认位置：在用户面前约 1m 处，键盘水平放置
        let centerPoint = SIMD3<Float>(0, 1.0, -1.0)
        let originWorld = centerPoint - xAxis * (Self.totalKeyboardLengthMeters / 2)

        let transform = simd_float4x4(columns: (
            SIMD4<Float>(xAxis, 0),
            SIMD4<Float>(yAxisWorld, 0),
            SIMD4<Float>(zAxis, 0),
            SIMD4<Float>(originWorld, 1)
        ))

        state = .placed(worldFromKeyboard: transform)
    }
    #endif

    func update(fingerTips: [String: SIMD3<Float>]) {
        guard case .placing = state else { return }

        guard let reticlePoint = fingerTips["right-indexFingerTip"] ?? fingerTips["left-indexFingerTip"] else {
            return
        }

        let isPinching = checkPinch(fingerTips: fingerTips)
        let shouldConfirm = isPinching && wasPinching == false
        wasPinching = isPinching

        if shouldConfirm {
            confirmPlacement(at: reticlePoint)
        } else {
            state = .placing(reticlePoint: reticlePoint)
        }
    }

    private func checkPinch(fingerTips: [String: SIMD3<Float>]) -> Bool {
        guard
            let index = fingerTips["right-indexFingerTip"],
            let thumb = fingerTips["right-thumbTip"]
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

        state = .placed(worldFromKeyboard: transform)
    }

    func updatePlacedTransformIfNeeded(_ worldFromKeyboard: simd_float4x4) -> Bool {
        guard case let .placed(existing) = state else { return false }
        guard existing != worldFromKeyboard else { return false }
        state = .placed(worldFromKeyboard: worldFromKeyboard)
        return true
    }
}
