import RealityKit
import SwiftUI
import UIKit

@MainActor
final class KeyboardAxesDebugOverlayController {
    private var rootEntity = Entity()
    private var axesRootEntity = Entity()
    private var hasAttachedRoot = false
    private var hasBuiltAxes = false

    func update(isEnabled: Bool, keyboardFrame: KeyboardFrame?, content: RealityViewContent) {
        guard isEnabled else {
            if hasAttachedRoot {
                rootEntity.isEnabled = false
            }
            return
        }

        guard let keyboardFrame else {
            if hasAttachedRoot {
                rootEntity.isEnabled = false
            }
            return
        }

        if hasAttachedRoot == false {
            content.add(rootEntity)
            rootEntity.addChild(axesRootEntity)
            hasAttachedRoot = true
        }

        if hasBuiltAxes == false {
            buildAxes()
            hasBuiltAxes = true
        }

        rootEntity.isEnabled = true
        axesRootEntity.transform = Transform(matrix: keyboardFrame.worldFromKeyboard)
    }

    private func buildAxes() {
        let thickness: Float = 0.004
        let xLen: Float = 0.30
        let yLen: Float = 0.18
        let zLen: Float = 0.20
        let labelFontSize: CGFloat = 0.08
        let labelExtrusion: Float = 0.004
        let labelOffset: Float = 0.02

        let xAxis = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(xLen, thickness, thickness)),
            materials: [SimpleMaterial(color: .systemRed, isMetallic: false)]
        )
        xAxis.position = SIMD3<Float>(xLen / 2, 0, 0)

        let yAxis = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(thickness, yLen, thickness)),
            materials: [SimpleMaterial(color: .systemGreen, isMetallic: false)]
        )
        yAxis.position = SIMD3<Float>(0, yLen / 2, 0)

        let zAxis = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(thickness, thickness, zLen)),
            materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)]
        )
        zAxis.position = SIMD3<Float>(0, 0, zLen / 2)

        axesRootEntity.addChild(xAxis)
        axesRootEntity.addChild(yAxis)
        axesRootEntity.addChild(zAxis)

        // Axis labels (X/Y/Z) near the positive ends.
        let xLabel = axisLabelEntity(text: "X", color: .systemRed, fontSize: labelFontSize, extrusion: labelExtrusion)
        xLabel.position = SIMD3<Float>(xLen + labelOffset, 0, 0)
        axesRootEntity.addChild(xLabel)

        let yLabel = axisLabelEntity(text: "Y", color: .systemGreen, fontSize: labelFontSize, extrusion: labelExtrusion)
        yLabel.position = SIMD3<Float>(0, yLen + labelOffset, 0)
        axesRootEntity.addChild(yLabel)

        let zLabel = axisLabelEntity(text: "Z", color: .systemBlue, fontSize: labelFontSize, extrusion: labelExtrusion)
        zLabel.position = SIMD3<Float>(0, 0, zLen + labelOffset)
        axesRootEntity.addChild(zLabel)
    }

    private func axisLabelEntity(text: String, color: UIColor, fontSize: CGFloat, extrusion: Float) -> ModelEntity {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: extrusion,
            font: font,
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byClipping
        )
        return ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
    }
}
