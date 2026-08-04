import Foundation


public struct MusicXMLFermataTimeline: Equatable, Sendable {
    public struct Hold: Equatable, Sendable {
        public let tick: Int
        public let performedOccurrenceIndex: Int
        public let extraTicks: Int
        public let sourceDirectionID: MusicXMLDirectionSourceID?
        public let contributingPerformedNoteIDs: [MusicXMLPerformedNoteID]
        public let provenanceSourceIdentities: [String]
    }

    public let holds: [Hold]
    public let interpretationProfileID: String

    public init(
        fermataEvents: [MusicXMLFermataEvent],
        notes: [MusicXMLNoteEvent],
        interpretationProfile: MusicXMLInterpretationProfile = .generic
    ) {
        interpretationProfileID = interpretationProfile.id
        let groups = Dictionary(grouping: fermataEvents) {
            EventKey(tick: $0.tick, performedOccurrenceIndex: $0.performedOccurrenceIndex)
        }
        holds = groups.compactMap { key, events in
            let matchingNotes = notes.filter { note in
                note.isRest == false
                    && note.tick == key.tick
                    && note.performedOccurrenceIndex == key.performedOccurrenceIndex
                    && events.contains { event in
                        event.scope.partID == note.partID
                            && (event.scope.staff == nil || event.scope.staff == note.staff)
                            && (event.scope.voice == nil || event.scope.voice == note.voice)
                    }
            }
            let performedNoteIDs = matchingNotes.compactMap(\.performedID).sorted {
                $0.description < $1.description
            }
            guard performedNoteIDs.isEmpty == false else { return nil }

            let baseDuration = max(1, matchingNotes.map(\.durationTicks).max() ?? 0)
            let sourceDirectionID = events.compactMap(\.sourceID).sorted {
                $0.description < $1.description
            }.first
            let provenanceSourceIdentities = Set(
                events.compactMap { $0.performedID?.description } + performedNoteIDs.map(\.description)
            ).sorted()
            return Hold(
                tick: key.tick,
                performedOccurrenceIndex: key.performedOccurrenceIndex,
                extraTicks: interpretationProfile.fermataExtraTicks(forBaseDurationTicks: baseDuration),
                sourceDirectionID: sourceDirectionID,
                contributingPerformedNoteIDs: performedNoteIDs,
                provenanceSourceIdentities: provenanceSourceIdentities
            )
        }.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.performedOccurrenceIndex != rhs.performedOccurrenceIndex {
                return lhs.performedOccurrenceIndex < rhs.performedOccurrenceIndex
            }
            return lhs.provenanceSourceIdentities.lexicographicallyPrecedes(rhs.provenanceSourceIdentities)
        }
    }
}

private extension MusicXMLFermataTimeline {
    struct EventKey: Hashable {
        let tick: Int
        let performedOccurrenceIndex: Int
    }
}
