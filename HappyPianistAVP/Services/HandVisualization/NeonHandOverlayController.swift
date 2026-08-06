import Foundation
import Metal
import RealityKit
import simd
import SwiftUI
import UIKit

@MainActor
final class NeonHandOverlayController {
    private struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>

        static let attributes: [LowLevelMesh.Attribute] = [
            .init(
                semantic: .position,
                format: .float3,
                layoutIndex: 0,
                offset: MemoryLayout<Self>.offset(of: \.position)!
            ),
            .init(
                semantic: .normal,
                format: .float3,
                layoutIndex: 0,
                offset: MemoryLayout<Self>.offset(of: \.normal)!
            ),
        ]

        static let layouts = [
            LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<Self>.stride),
        ]
    }

    private struct HandRuntime {
        let mesh: LowLevelMesh
        let entity: ModelEntity
    }

    private let rootEntity: Entity
    private var leftHand: HandRuntime?
    private var rightHand: HandRuntime?
    private var updateTask: Task<Void, Never>?
    private var hasAttachedRoot = false
    private var reduceMotionEnabled = false

    init(rootEntity: Entity = Entity()) {
        self.rootEntity = rootEntity
    }

    func update(
        isEnabled: Bool,
        trackingService: any ARTrackingServiceProtocol,
        reduceMotion: Bool,
        content: RealityViewContent
    ) {
        #if targetEnvironment(simulator)
            if reduceMotionEnabled != reduceMotion {
                stopUpdates()
            }
        #endif
        reduceMotionEnabled = reduceMotion
        guard isEnabled else {
            stopUpdates()
            setHandsHidden()
            return
        }

        if hasAttachedRoot == false {
            content.add(rootEntity)
            hasAttachedRoot = true
        }
        rootEntity.isEnabled = true
        ensureHandEntities()
        startUpdatesIfNeeded(trackingService: trackingService)
    }

    func reset() {
        stopUpdates()
        while let child = rootEntity.children.first {
            rootEntity.children.remove(child)
        }
        rootEntity.removeFromParent()
        leftHand = nil
        rightHand = nil
        hasAttachedRoot = false
    }

    private func startUpdatesIfNeeded(trackingService: any ARTrackingServiceProtocol) {
        guard updateTask == nil else { return }

        #if targetEnvironment(simulator)
            guard reduceMotionEnabled == false else {
                apply(snapshot: NeonHandSimulatorPose.snapshot(phase: 0))
                return
            }
            updateTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while Task.isCancelled == false {
                    apply(snapshot: NeonHandSimulatorPose.snapshot(phase: Float(ProcessInfo.processInfo.systemUptime)))
                    do {
                        try await Task.sleep(for: .milliseconds(33))
                    } catch {
                        return
                    }
                }
            }
        #else
            let updates = trackingService.handSkeletonUpdatesStream()
            updateTask = Task { @MainActor [weak self] in
                guard let self else { return }
                for await snapshot in updates {
                    guard Task.isCancelled == false else { return }
                    apply(snapshot: snapshot)
                }
            }
        #endif
    }

    private func stopUpdates() {
        updateTask?.cancel()
        updateTask = nil
    }

    private func ensureHandEntities() {
        if leftHand == nil, let runtime = makeHandRuntime() {
            rootEntity.addChild(runtime.entity)
            leftHand = runtime
        }
        if rightHand == nil, let runtime = makeHandRuntime() {
            rootEntity.addChild(runtime.entity)
            rightHand = runtime
        }
    }

    private func makeHandRuntime() -> HandRuntime? {
        do {
            var descriptor = LowLevelMesh.Descriptor()
            descriptor.vertexAttributes = Vertex.attributes
            descriptor.vertexLayouts = Vertex.layouts
            descriptor.vertexCapacity = NeonHandSurface.vertexCount
            descriptor.indexCapacity = NeonHandSurface.triangleIndices.count
            descriptor.indexType = .uint32
            let mesh = try LowLevelMesh(descriptor: descriptor)
            mesh.withUnsafeMutableIndices { rawIndices in
                let indices = rawIndices.bindMemory(to: UInt32.self)
                for (index, value) in NeonHandSurface.triangleIndices.enumerated() {
                    indices[index] = value
                }
            }
            mesh.parts.replaceAll([
                LowLevelMesh.Part(
                    indexCount: NeonHandSurface.triangleIndices.count,
                    topology: .triangle,
                    bounds: BoundingBox(
                        min: SIMD3<Float>(repeating: -2),
                        max: SIMD3<Float>(repeating: 2)
                    )
                ),
            ])

            let entity = ModelEntity(
                mesh: try MeshResource(from: mesh),
                materials: [makeMaterial()]
            )
            entity.isEnabled = false
            return HandRuntime(mesh: mesh, entity: entity)
        } catch {
            return nil
        }
    }

    private func makeMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .cyan)
        material.blending = .transparent(opacity: 0.46)
        material.sheen = .init(tint: .white)
        material.emissiveColor = .init(color: .magenta)
        material.emissiveIntensity = 1.35
        material.roughness = 0.24
        material.metallic = 0.08
        return material
    }

    private func apply(snapshot: HandSkeletonSnapshot) {
        update(leftHand, with: snapshot.left)
        update(rightHand, with: snapshot.right)
    }

    private func update(_ runtime: HandRuntime?, with skeleton: TrackedHandSkeleton) {
        guard let runtime else { return }
        guard let geometry = NeonHandSurface.geometry(for: skeleton) else {
            runtime.entity.isEnabled = false
            return
        }

        runtime.mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBytes in
            let vertices = rawBytes.bindMemory(to: Vertex.self)
            for index in geometry.positions.indices {
                vertices[index] = Vertex(
                    position: geometry.positions[index],
                    normal: geometry.normals[index]
                )
            }
        }
        runtime.entity.isEnabled = true
    }

    private func setHandsHidden() {
        leftHand?.entity.isEnabled = false
        rightHand?.entity.isEnabled = false
    }
}

#if targetEnvironment(simulator)
    enum NeonHandSimulatorPose {
        static func snapshot(phase: Float) -> HandSkeletonSnapshot {
            HandSkeletonSnapshot(
                left: makeHand(side: .left, phase: phase),
                right: makeHand(side: .right, phase: phase + .pi)
            )
        }

        private static func makeHand(side: TrackedHandSide, phase: Float) -> TrackedHandSkeleton {
            let isLeft = side == .left
            let wrist = SIMD3<Float>(isLeft ? -0.16 : 0.16, -0.24, -0.52)
            let inward: Float = isLeft ? 1 : -1
            let curl = sin(phase * 1.7) * 0.007
            var joints = Dictionary(
                uniqueKeysWithValues: TrackedHandJoint.allCases.map { ($0, wrist) }
            )
            joints[.forearmArm] = wrist + SIMD3<Float>(0, -0.12, 0.04)
            joints[.forearmWrist] = wrist + SIMD3<Float>(0, -0.05, 0.015)
            joints[.wrist] = wrist
            joints[.thumbKnuckle] = wrist + SIMD3<Float>(inward * 0.032, 0.020, 0)
            joints[.thumbIntermediateBase] = wrist + SIMD3<Float>(inward * 0.050, 0.034, curl)
            joints[.thumbIntermediateTip] = wrist + SIMD3<Float>(inward * 0.062, 0.047, curl * 1.6)
            joints[.thumbTip] = wrist + SIMD3<Float>(inward * 0.071, 0.060, curl * 2)
            addFinger(
                [.indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip],
                start: wrist + SIMD3<Float>(inward * 0.026, 0.027, 0),
                curl: curl,
                joints: &joints
            )
            addFinger(
                [.middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip],
                start: wrist + SIMD3<Float>(0, 0.031, 0),
                curl: curl,
                joints: &joints
            )
            addFinger(
                [.ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip],
                start: wrist + SIMD3<Float>(inward * -0.024, 0.028, 0),
                curl: curl,
                joints: &joints
            )
            addFinger(
                [.littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip],
                start: wrist + SIMD3<Float>(inward * -0.046, 0.021, 0),
                curl: curl,
                joints: &joints
            )
            return TrackedHandSkeleton(isTracked: true, joints: joints)
        }

        private static func addFinger(
            _ chain: [TrackedHandJoint],
            start: SIMD3<Float>,
            curl: Float,
            joints: inout [TrackedHandJoint: SIMD3<Float>]
        ) {
            for (index, joint) in chain.enumerated() {
                let progress = Float(index)
                joints[joint] = start + SIMD3<Float>(0, progress * 0.021, curl * progress)
            }
        }
    }
#endif
