import Foundation

extension MusicXMLScore {
    func preferredPrimaryPartID(preferredPartID: String = "P1") -> String {
        let available = Set(notes.map(\.partID))
        if available.contains(preferredPartID) {
            return preferredPartID
        }

        var countByPartID: [String: Int] = [:]
        countByPartID.reserveCapacity(available.count)

        for note in notes where note.isRest == false && note.midiNote != nil {
            countByPartID[note.partID, default: 0] += 1
        }

        if let best = countByPartID.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        })?.key {
            return best
        }

        return notes.first?.partID ?? preferredPartID
    }

    func filtering(toPartID partID: String) -> MusicXMLScore {
        MusicXMLScore(
            scoreVersion: scoreVersion,
            notes: notes.filter { $0.partID == partID },
            tempoEvents: tempoEvents.filter { $0.scope.partID == partID },
            soundDirectives: soundDirectives.filter { $0.partID == partID },
            pedalEvents: pedalEvents.filter { $0.partID == partID },
            dynamicEvents: dynamicEvents.filter { $0.scope.partID == partID },
            wedgeEvents: wedgeEvents.filter { $0.scope.partID == partID },
            fermataEvents: fermataEvents.filter { $0.scope.partID == partID },
            slurEvents: slurEvents.filter { $0.scope.partID == partID },
            timeSignatureEvents: timeSignatureEvents.filter { $0.scope.partID == partID },
            keySignatureEvents: keySignatureEvents.filter { $0.scope.partID == partID },
            clefEvents: clefEvents.filter { $0.scope.partID == partID },
            wordsEvents: wordsEvents.filter { $0.scope.partID == partID },
            measures: measures.filter { $0.partID == partID },
            repeatDirectives: repeatDirectives.filter { $0.partID == partID },
            endingDirectives: endingDirectives.filter { $0.partID == partID }
        )
    }
}
