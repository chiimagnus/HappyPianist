import Foundation
import Practice

struct PianoDemonstrationFingeringPlan: Equatable {
    let transportGeneration: Int?
    let geometryCacheID: UUID
    let plan: PianoFingeringPlanner.Plan
}

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
        case fingeringUnplanned
        case assetUnavailable
        case unreachable
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

    func limitedToAvailableHands(
        _ availableHands: Set<PianoDemonstrationHand>
    ) -> PianoDemonstrationHandCoverage {
        let unavailableTargets = coveredTargets.filter { availableHands.contains($0.hand) == false }
        let assetFailures = unavailableTargets.map {
            UncoveredKey(
                midiNote: $0.midiNote,
                occurrenceID: $0.occurrenceID,
                reason: .assetUnavailable
            )
        }
        return PianoDemonstrationHandCoverage(
            guideID: guideID,
            coveredTargets: coveredTargets.filter { availableHands.contains($0.hand) },
            uncoveredKeys: (uncoveredKeys + assetFailures).sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                if lhs.occurrenceID != rhs.occurrenceID { return lhs.occurrenceID < rhs.occurrenceID }
                return lhs.reason.rawValue < rhs.reason.rawValue
            },
            releasedMIDINotes: releasedMIDINotes
        )
    }

    func markingUnreachable(
        occurrenceIDs: Set<String>
    ) -> PianoDemonstrationHandCoverage {
        guard occurrenceIDs.isEmpty == false else { return self }
        let unreachableTargets = coveredTargets.filter {
            occurrenceIDs.contains($0.occurrenceID)
        }
        guard unreachableTargets.isEmpty == false else { return self }
        let unreachableKeys = unreachableTargets.map {
            UncoveredKey(
                midiNote: $0.midiNote,
                occurrenceID: $0.occurrenceID,
                reason: .unreachable
            )
        }
        return PianoDemonstrationHandCoverage(
            guideID: guideID,
            coveredTargets: coveredTargets.filter {
                occurrenceIDs.contains($0.occurrenceID) == false
            },
            uncoveredKeys: (uncoveredKeys + unreachableKeys).sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote { return lhs.midiNote < rhs.midiNote }
                if lhs.occurrenceID != rhs.occurrenceID { return lhs.occurrenceID < rhs.occurrenceID }
                return lhs.reason.rawValue < rhs.reason.rawValue
            },
            releasedMIDINotes: releasedMIDINotes
        )
    }
}
