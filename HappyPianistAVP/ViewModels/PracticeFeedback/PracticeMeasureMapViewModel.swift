struct PracticeMeasureMapItem: Equatable, Identifiable {
    let id: PracticeSourceMeasureID
    let displayNumber: String
    let state: MeasureLearningState
    let isCurrentPassage: Bool
    let isCurrentMeasure: Bool
    let isHotspot: Bool
}

struct PracticeMeasureMapViewModel: Equatable {
    let items: [PracticeMeasureMapItem]

    init(
        measureSpans: [MusicXMLMeasureSpan],
        progress: SongPracticeProgress?,
        handMode: PracticeHandMode,
        currentPassage: PracticePassage?,
        currentMeasure: PracticeSourceMeasureID?
    ) {
        let facts = progress?.measureFacts.filter { $0.handMode == handMode } ?? []
        let hotspot = PracticeHotspotPolicy().hotspot(in: facts)?.sourceMeasureID
        var seen: Set<PracticeSourceMeasureID> = []
        items = measureSpans.compactMap { span in
            let id = span.occurrenceID.sourceMeasureID
            guard seen.insert(id).inserted else { return nil }
            let state = facts.first { $0.sourceMeasureID == id }?.state ?? .notStarted
            let occurrence = span.occurrenceID.occurrenceIndex
            return PracticeMeasureMapItem(
                id: id,
                displayNumber: id.sourceNumberToken ?? "\(id.sourceMeasureIndex + 1)",
                state: state,
                isCurrentPassage: currentPassage.map { $0.start.occurrenceIndex <= occurrence && occurrence <= $0.end.occurrenceIndex } ?? false,
                isCurrentMeasure: id == currentMeasure,
                isHotspot: id == hotspot
            )
        }
    }
}
