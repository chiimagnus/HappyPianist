import Foundation

extension MusicXMLScore {
    func filtering(toLogicalInstrument instrument: MusicXMLLogicalInstrument) -> MusicXMLScore {
        filtering(toPartIDs: Set(instrument.memberPartIDs), selectedLogicalInstrument: instrument)
    }

    func filtering(toPartID partID: String) -> MusicXMLScore {
        let selected = logicalInstruments.first { $0.memberPartIDs == [partID] }
        return filtering(toPartIDs: [partID], selectedLogicalInstrument: selected)
    }

    private func filtering(
        toPartIDs partIDs: Set<String>,
        selectedLogicalInstrument: MusicXMLLogicalInstrument?
    ) -> MusicXMLScore {
        MusicXMLScore(
            scoreVersion: scoreVersion,
            partMetadata: partMetadata.filter { partIDs.contains($0.partID) },
            logicalInstruments: selectedLogicalInstrument.map { [$0] } ?? [],
            notes: notes.filter { partIDs.contains($0.partID) },
            tempoEvents: tempoEvents.filter { partIDs.contains($0.scope.partID) },
            soundDirectives: soundDirectives.filter { partIDs.contains($0.partID) },
            pedalEvents: pedalEvents.filter { partIDs.contains($0.partID) },
            dynamicEvents: dynamicEvents.filter { partIDs.contains($0.scope.partID) },
            wedgeEvents: wedgeEvents.filter { partIDs.contains($0.scope.partID) },
            fermataEvents: fermataEvents.filter { partIDs.contains($0.scope.partID) },
            timeSignatureEvents: timeSignatureEvents.filter { partIDs.contains($0.scope.partID) },
            keySignatureEvents: keySignatureEvents.filter { partIDs.contains($0.scope.partID) },
            clefEvents: clefEvents.filter { partIDs.contains($0.scope.partID) },
            transposeEvents: transposeEvents.filter { partIDs.contains($0.scope.partID) },
            octaveShiftEvents: octaveShiftEvents.filter { partIDs.contains($0.scope.partID) },
            wordsEvents: wordsEvents.filter { partIDs.contains($0.scope.partID) },
            measures: measures.filter { partIDs.contains($0.partID) },
            repeatDirectives: repeatDirectives.filter { partIDs.contains($0.partID) },
            endingDirectives: endingDirectives.filter { partIDs.contains($0.partID) }
        )
    }
}
