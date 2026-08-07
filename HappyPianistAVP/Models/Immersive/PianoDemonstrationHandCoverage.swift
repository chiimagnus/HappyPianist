struct PianoDemonstrationHandCoverage: Equatable {
    struct UncoveredKey: Equatable, Identifiable {
        var id: String {
            occurrenceID
        }

        let midiNote: Int
        let occurrenceID: String
        let reason: Reason
    }

    enum Reason: String, Equatable, Hashable {
        case unknownHand
        case fingeringConflict
        case tooManyFingers
        case spanExceeded
        case missingGeometry
    }

    let guideID: Int?
    let coveredTargets: [PianoDemonstrationHandTarget]
    let uncoveredKeys: [UncoveredKey]
    let releasedMIDINotes: Set<Int>

    init(
        guideID: Int? = nil,
        coveredTargets: [PianoDemonstrationHandTarget] = [],
        uncoveredKeys: [UncoveredKey] = [],
        releasedMIDINotes: Set<Int> = []
    ) {
        self.guideID = guideID
        self.coveredTargets = coveredTargets
        self.uncoveredKeys = uncoveredKeys
        self.releasedMIDINotes = releasedMIDINotes
    }

    func coveredTargets(for hand: PianoDemonstrationHand) -> [PianoDemonstrationHandTarget] {
        coveredTargets.filter { $0.hand == hand }
    }
}
