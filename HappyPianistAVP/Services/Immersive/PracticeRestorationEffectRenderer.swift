import RealityKit
import UIKit

@MainActor
final class PracticeRestorationEffectRenderer {
    private let sleeper: any SleeperProtocol
    private var entity: ModelEntity?
    private var removalTask: Task<Void, Never>?
    private var lastEvent: PracticeFeedbackEvent?
    private(set) var activeEffectCount = 0

    init(sleeper: any SleeperProtocol = TaskSleeper()) {
        self.sleeper = sleeper
    }

    func update(event: PracticeFeedbackEvent?, parent: Entity, reduceMotion: Bool) {
        guard event != lastEvent else { return }
        lastEvent = event
        guard event != nil else {
            reset(clearEvent: false)
            return
        }
        guard let event, event.kind.isRestorationEffect else { return }
        reset(clearEvent: false)
        var material = UnlitMaterial(color: event.kind.isStable ? .systemYellow : .systemTeal)
        material.blending = .transparent(opacity: .init(floatLiteral: reduceMotion ? 0.35 : 0.65))
        let mesh: MeshResource = event.kind.isStable
            ? .generateSphere(radius: 0.025)
            : .generateBox(size: SIMD3<Float>(0.12, 0.002, 0.025))
        let effect = ModelEntity(mesh: mesh, materials: [material])
        effect.position = [0, 0.012, 0]
        parent.addChild(effect)
        entity = effect
        activeEffectCount = 1
        removalTask = Task { [weak self, sleeper] in
            try? await sleeper.sleep(for: .seconds(1))
            guard Task.isCancelled == false else { return }
            self?.reset(clearEvent: false)
        }
    }

    func reset() {
        reset(clearEvent: true)
    }

    private func reset(clearEvent: Bool) {
        removalTask?.cancel()
        removalTask = nil
        entity?.removeFromParent()
        entity = nil
        activeEffectCount = 0
        if clearEvent { lastEvent = nil }
    }
}

private extension PracticeFeedbackEventKind {
    var isStable: Bool {
        switch self { case .measureStable, .passageStable: true; default: false }
    }

    var isRestorationEffect: Bool {
        switch self { case .retryInvitation, .measureStable: true; default: false }
    }
}
