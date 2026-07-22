struct PracticeHotspotPolicy {
    func hotspot(for decision: CoachingDecision?) -> PracticeHotspot? {
        decision?.issue.measureOccurrenceIDs.first.map {
            PracticeHotspot(sourceMeasureID: $0.sourceMeasureID)
        }
    }
}
