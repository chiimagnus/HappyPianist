struct PracticeMeasureMapItem: Equatable, Identifiable {
    let id: PracticeSourceMeasureID
    let displayNumber: String
    let state: MeasurePitchStepLearningState
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
        let currentSourceMeasureIDs = Set(measureSpans.compactMap { span -> PracticeSourceMeasureID? in
            guard let currentPassage,
                  currentPassage.start.occurrenceIndex <= span.occurrenceIndex,
                  span.occurrenceIndex <= currentPassage.end.occurrenceIndex
            else { return nil }
            return span.occurrenceID.sourceMeasureID
        })
        let hotspotFacts = currentPassage == nil
            ? facts
            : facts.filter { currentSourceMeasureIDs.contains($0.sourceMeasureID) }
        let hotspot = PracticeHotspotPolicy().hotspot(in: hotspotFacts)?.sourceMeasureID
        var seen: Set<PracticeSourceMeasureID> = []
        items = measureSpans.compactMap { span in
            let id = span.occurrenceID.sourceMeasureID
            guard seen.insert(id).inserted else { return nil }
            let state = facts.first { $0.sourceMeasureID == id }?.state ?? .notStarted
            return PracticeMeasureMapItem(
                id: id,
                displayNumber: id.sourceNumberToken ?? "\(id.sourceMeasureIndex + 1)",
                state: state,
                isCurrentPassage: currentSourceMeasureIDs.contains(id),
                isCurrentMeasure: id == currentMeasure,
                isHotspot: id == hotspot
            )
        }
    }
}
