import Foundation

struct MusicXMLPracticePartSelector {
    func select(from score: MusicXMLScore) -> MusicXMLPracticePartSelection {
        let playable = score.logicalInstruments.filter { instrument in
            score.notes.contains { note in
                instrument.memberPartIDs.contains(note.partID) && note.isRest == false && note.midiNote != nil
            }
        }
        let explicitPianos = playable.filter { $0.classification == .piano }

        if explicitPianos.count == 1, let piano = explicitPianos.first {
            return .selected(piano)
        }
        if explicitPianos.count > 1 {
            return .ambiguous(MusicXMLPartSelectionAmbiguity(
                candidateInstrumentIDs: explicitPianos.map(\.id).sorted(),
                reason: "multiple-explicit-piano-instruments"
            ))
        }
        if playable.count == 1, let only = playable.first {
            return .selected(only)
        }
        if playable.isEmpty {
            return .unavailable
        }
        return .ambiguous(MusicXMLPartSelectionAmbiguity(
            candidateInstrumentIDs: playable.map(\.id).sorted(),
            reason: "multiple-playable-instruments-without-piano-evidence"
        ))
    }

    func structuralPartID(
        for instrument: MusicXMLLogicalInstrument,
        in score: MusicXMLScore
    ) -> String? {
        let memberIDs = Set(instrument.memberPartIDs)
        guard memberIDs.isEmpty == false else { return nil }

        let sourceOrder = score.partMetadata.map(\.partID) + instrument.memberPartIDs
        let orderedMembers = sourceOrder.reduce(into: [String]()) { result, partID in
            guard memberIDs.contains(partID), result.contains(partID) == false else { return }
            result.append(partID)
        }
        let structureCounts = Dictionary(uniqueKeysWithValues: orderedMembers.map { partID in
            let count = score.repeatDirectives.count { $0.partID == partID }
                + score.endingDirectives.count { $0.partID == partID }
                + score.soundDirectives.count { directive in
                    directive.partID == partID && (
                        directive.segno != nil || directive.coda != nil || directive.tocoda != nil
                            || directive.dalsegno != nil || directive.dacapo != nil
                    )
                }
            return (partID, count)
        })
        let highestCount = structureCounts.values.max() ?? 0
        if highestCount > 0 {
            return orderedMembers.first { structureCounts[$0] == highestCount }
        }
        return orderedMembers.first { partID in
            score.measures.contains { $0.partID == partID }
        }
    }

}
