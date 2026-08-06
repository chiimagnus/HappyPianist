import simd

enum PianoDemonstrationHand: CaseIterable, Equatable, Hashable {
    case left
    case right
}

enum PianoDemonstrationFinger: Int, CaseIterable, Equatable, Hashable {
    case thumb = 1
    case index
    case middle
    case ring
    case little
}

enum PianoDemonstrationTouchPhase: Equatable {
    case triggered
    case held
}

struct PianoDemonstrationHandTarget: Equatable, Identifiable {
    var id: String {
        occurrenceID
    }

    let occurrenceID: String
    let hand: PianoDemonstrationHand
    let finger: PianoDemonstrationFinger
    let midiNote: Int
    let phase: PianoDemonstrationTouchPhase
    let contactPositionLocal: SIMD3<Float>
    let velocity: UInt8
}

struct PianoDemonstrationHandTargets: Equatable {
    static let empty = PianoDemonstrationHandTargets()

    let guideID: Int?
    let targets: [PianoDemonstrationHandTarget]
    let releasedMIDINotes: Set<Int>

    init(
        guideID: Int? = nil,
        targets: [PianoDemonstrationHandTarget] = [],
        releasedMIDINotes: Set<Int> = []
    ) {
        self.guideID = guideID
        self.targets = targets
        self.releasedMIDINotes = releasedMIDINotes
    }

    func targets(for hand: PianoDemonstrationHand) -> [PianoDemonstrationHandTarget] {
        targets.filter { $0.hand == hand }
    }
}
