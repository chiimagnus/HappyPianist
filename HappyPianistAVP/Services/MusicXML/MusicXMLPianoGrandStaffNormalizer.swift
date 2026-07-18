import Foundation

struct MusicXMLPianoGrandStaffNormalizer {
    func normalize(score: MusicXMLScore) -> MusicXMLScore {
        var copy = score
        copy.logicalInstruments = classifyLogicalInstruments(in: score)
        return copy
    }

    private func classifyLogicalInstruments(in score: MusicXMLScore) -> [MusicXMLLogicalInstrument] {
        let partIDs = allPartIDs(in: score)
        let metadataByPartID = Dictionary(uniqueKeysWithValues: score.partMetadata.map { ($0.partID, $0) })
        let explicitPianoPartIDs = partIDs.filter { partID in
            metadataByPartID[partID].map(isExplicitPiano) == true
        }

        var consumed = Set<String>()
        var output: [MusicXMLLogicalInstrument] = []

        if let splitPair = splitKeyboardPair(
            partIDs: explicitPianoPartIDs,
            metadataByPartID: metadataByPartID
        ) {
            let members = [splitPair.upper, splitPair.lower].sorted()
            output.append(MusicXMLLogicalInstrument(
                id: logicalInstrumentID(classification: .piano, partIDs: members),
                memberPartIDs: members,
                classification: .piano,
                evidence: [
                    MusicXMLLogicalInstrumentEvidence(
                        kind: .explicitPianoMetadata,
                        partIDs: members
                    ),
                    MusicXMLLogicalInstrumentEvidence(
                        kind: .splitKeyboardPartNames,
                        partIDs: members
                    ),
                ]
            ))
            consumed.formUnion(members)
        }

        for partID in partIDs where consumed.contains(partID) == false {
            let metadata = metadataByPartID[partID]
            let classification: MusicXMLLogicalInstrumentClassification = if metadata.map(isExplicitPiano) == true {
                .piano
            } else if metadata == nil {
                .unknown
            } else {
                .other
            }
            let evidenceKind: MusicXMLLogicalInstrumentEvidenceKind = switch classification {
            case .piano:
                .explicitPianoMetadata
            case .other:
                .singlePlayablePart
            case .unknown:
                .unresolvedMetadata
            }
            output.append(MusicXMLLogicalInstrument(
                id: logicalInstrumentID(classification: classification, partIDs: [partID]),
                memberPartIDs: [partID],
                classification: classification,
                evidence: [MusicXMLLogicalInstrumentEvidence(kind: evidenceKind, partIDs: [partID])]
            ))
        }

        return output.sorted { $0.id < $1.id }
    }

    private func allPartIDs(in score: MusicXMLScore) -> [String] {
        var ids = Set(score.partMetadata.map(\.partID))
        ids.formUnion(score.notes.map(\.partID))
        ids.formUnion(score.measures.map(\.partID))
        ids.formUnion(score.tempoEvents.map(\.scope.partID))
        ids.formUnion(score.soundDirectives.map(\.partID))
        ids.formUnion(score.pedalEvents.map(\.partID))
        ids.formUnion(score.dynamicEvents.map(\.scope.partID))
        ids.formUnion(score.wedgeEvents.map(\.scope.partID))
        ids.formUnion(score.fermataEvents.map(\.scope.partID))
        ids.formUnion(score.timeSignatureEvents.map(\.scope.partID))
        ids.formUnion(score.keySignatureEvents.map(\.scope.partID))
        ids.formUnion(score.clefEvents.map(\.scope.partID))
        ids.formUnion(score.transposeEvents.map(\.scope.partID))
        ids.formUnion(score.octaveShiftEvents.map(\.scope.partID))
        ids.formUnion(score.wordsEvents.map(\.scope.partID))
        return ids.sorted()
    }

    private func isExplicitPiano(_ metadata: MusicXMLPartMetadata) -> Bool {
        let tokens = [metadata.name, metadata.abbreviation]
            + metadata.scoreInstruments.map(\.name)
        return tokens.compactMap { $0 }.contains { normalizedToken($0).contains("piano") }
    }

    private func splitKeyboardPair(
        partIDs: [String],
        metadataByPartID: [String: MusicXMLPartMetadata]
    ) -> (upper: String, lower: String)? {
        let roles = partIDs.compactMap { partID -> (String, KeyboardRole, String)? in
            guard let name = metadataByPartID[partID]?.name,
                  let role = keyboardRole(in: name)
            else { return nil }
            return (partID, role, keyboardBaseName(name))
        }
        guard roles.count == 2,
              let upper = roles.first(where: { $0.1 == .upper }),
              let lower = roles.first(where: { $0.1 == .lower }),
              upper.2.isEmpty == false,
              upper.2 == lower.2
        else { return nil }
        return (upper.0, lower.0)
    }

    private enum KeyboardRole {
        case upper
        case lower
    }

    private func keyboardRole(in value: String) -> KeyboardRole? {
        let words = normalizedToken(value).split(separator: " ").map(String.init)
        if words.contains(where: { ["rh", "right", "upper", "treble", "primo"].contains($0) }) {
            return .upper
        }
        if words.contains(where: { ["lh", "left", "lower", "bass", "secondo"].contains($0) }) {
            return .lower
        }
        return nil
    }

    private func keyboardBaseName(_ value: String) -> String {
        let roleWords = Set(["rh", "right", "upper", "treble", "primo", "lh", "left", "lower", "bass", "secondo"])
        return normalizedToken(value)
            .split(separator: " ")
            .map(String.init)
            .filter { roleWords.contains($0) == false }
            .joined(separator: " ")
    }

    private func normalizedToken(_ value: String) -> String {
        value
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { result, character in
                if character == " ", result.last == " " { return }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logicalInstrumentID(
        classification: MusicXMLLogicalInstrumentClassification,
        partIDs: [String]
    ) -> String {
        "\(classification.rawValue):\(partIDs.sorted().joined(separator: "+"))"
    }
}
