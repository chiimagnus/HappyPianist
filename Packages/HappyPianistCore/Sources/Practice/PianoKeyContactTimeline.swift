import Foundation
import MusicXML

/// The transport-derived contact facts available to hand-motion planning.
///
/// `ScorePerformancePlan` supplies score facts, while the timeline and schedule supply
/// the only playable seconds. This type intentionally does not calculate time from ticks.
public struct PianoKeyContactTimeline: Equatable, Sendable {
    public enum UnplannableReason: String, Equatable, Sendable {
        case missingNoteOn
        case missingNoteOff
        case releasePrecedesOnset
    }

    public enum Timing: Equatable, Sendable {
        case scheduled(onsetSeconds: TimeInterval, releaseSeconds: TimeInterval)
        case unplannable(UnplannableReason)
    }

    public struct Contact: Equatable, Identifiable, Sendable {
        public let occurrenceID: String
        public let midiNote: Int
        public let staff: Int
        public let handAssignment: ScoreHandAssignment
        public let fingerings: [MusicXMLFingering]
        public let velocity: UInt8
        public let guideID: Int?
        public let stepIndex: Int?
        public let carriedIn: Bool
        public let timing: Timing

        public var id: String {
            occurrenceID
        }

        public var hand: ScoreHand {
            handAssignment.hand
        }

        public var onsetSeconds: TimeInterval? {
            guard case let .scheduled(onsetSeconds, _) = timing else { return nil }
            return onsetSeconds
        }

        public var releaseSeconds: TimeInterval? {
            guard case let .scheduled(_, releaseSeconds) = timing else { return nil }
            return releaseSeconds
        }

        public init(
            occurrenceID: String,
            midiNote: Int,
            staff: Int,
            handAssignment: ScoreHandAssignment,
            fingerings: [MusicXMLFingering],
            velocity: UInt8,
            guideID: Int?,
            stepIndex: Int?,
            carriedIn: Bool,
            timing: Timing
        ) {
            self.occurrenceID = occurrenceID
            self.midiNote = midiNote
            self.staff = staff
            self.handAssignment = handAssignment
            self.fingerings = fingerings
            self.velocity = velocity
            self.guideID = guideID
            self.stepIndex = stepIndex
            self.carriedIn = carriedIn
            self.timing = timing
        }
    }

    public let contacts: [Contact]

    public init(contacts: [Contact]) {
        self.contacts = contacts.sorted(by: Self.areInPresentationOrder)
    }

    public init(
        plan: ScorePerformancePlan,
        timeline: AutoplayPerformanceTimeline,
        schedule: AutoplayTimelineTimeSchedule,
        guideProjection: [PianoHighlightGuide],
        stepProjection: [PracticeStep]
    ) {
        let sourceEventIDs = Set(timeline.events.compactMap { event -> String? in
            guard let sourceEventID = event.sourceEventID else { return nil }
            switch event.kind {
            case .noteOn, .noteOff:
                return sourceEventID
            case .pauseSeconds, .controlChange, .tempo, .advanceStep, .advanceGuide:
                return nil
            }
        })
        let guideIDByOccurrenceID = Self.guideIDByOccurrenceID(
            guides: guideProjection,
            timeline: timeline
        )
        let stepEvents = timeline.events.compactMap { event -> (tick: Int, index: Int)? in
            guard case let .advanceStep(index) = event.kind,
                  stepProjection.indices.contains(index)
            else {
                return nil
            }
            return (event.tick, index)
        }

        contacts = plan.noteEvents.compactMap { note in
            let occurrenceID = note.id.description
            guard sourceEventIDs.contains(occurrenceID) else { return nil }

            let noteOnEvent = timeline.events.first { event in
                event.sourceEventID == occurrenceID && event.isNoteOn
            }
            let noteOffEvent = timeline.events.first { event in
                event.sourceEventID == occurrenceID && event.isNoteOff
            }
            let timing = Self.timing(
                noteOnEvent: noteOnEvent,
                noteOffEvent: noteOffEvent,
                schedule: schedule
            )
            let contactTick = noteOnEvent?.tick ?? noteOffEvent?.tick ?? note.performedOnTick

            return Contact(
                occurrenceID: occurrenceID,
                midiNote: note.midiNote,
                staff: note.staff,
                handAssignment: note.handAssignment,
                fingerings: note.fingerings,
                velocity: note.velocity,
                guideID: guideIDByOccurrenceID[occurrenceID],
                stepIndex: stepEvents.last(where: { $0.tick <= contactTick })?.index,
                carriedIn: noteOnEvent.map { $0.tick != note.performedOnTick } ?? false,
                timing: timing
            )
        }
        .sorted(by: Self.areInPresentationOrder)
    }

    public func contact(forOccurrenceID occurrenceID: String) -> Contact? {
        contacts.first { $0.occurrenceID == occurrenceID }
    }

    private static func guideIDByOccurrenceID(
        guides: [PianoHighlightGuide],
        timeline: AutoplayPerformanceTimeline
    ) -> [String: Int] {
        let availableGuideIndices = Set(timeline.events.compactMap { event -> Int? in
            guard case let .advanceGuide(index, _) = event.kind else { return nil }
            return index
        })
        var result: [String: Int] = [:]
        for (index, guide) in guides.enumerated() where availableGuideIndices.contains(index) {
            for note in guide.triggeredNotes + guide.activeNotes where result[note.occurrenceID] == nil {
                result[note.occurrenceID] = guide.id
            }
        }
        return result
    }

    private static func timing(
        noteOnEvent: AutoplayPerformanceTimeline.Event?,
        noteOffEvent: AutoplayPerformanceTimeline.Event?,
        schedule: AutoplayTimelineTimeSchedule
    ) -> Timing {
        guard let noteOnEvent else { return .unplannable(.missingNoteOn) }
        guard let noteOffEvent else { return .unplannable(.missingNoteOff) }
        guard let onsetSeconds = schedule.timeSeconds(forEventID: noteOnEvent.id) else {
            return .unplannable(.missingNoteOn)
        }
        guard let releaseSeconds = schedule.timeSeconds(forEventID: noteOffEvent.id) else {
            return .unplannable(.missingNoteOff)
        }
        guard releaseSeconds >= onsetSeconds else {
            return .unplannable(.releasePrecedesOnset)
        }
        return .scheduled(onsetSeconds: onsetSeconds, releaseSeconds: releaseSeconds)
    }

    private static func areInPresentationOrder(_ lhs: Contact, _ rhs: Contact) -> Bool {
        switch (lhs.onsetSeconds, rhs.onsetSeconds) {
        case let (lhsOnset?, rhsOnset?) where lhsOnset != rhsOnset:
            lhsOnset < rhsOnset
        case (.some, .none):
            true
        case (.none, .some):
            false
        default:
            lhs.occurrenceID < rhs.occurrenceID
        }
    }
}

private extension AutoplayPerformanceTimeline.Event {
    var isNoteOn: Bool {
        if case .noteOn = kind { return true }
        return false
    }

    var isNoteOff: Bool {
        if case .noteOff = kind { return true }
        return false
    }
}
