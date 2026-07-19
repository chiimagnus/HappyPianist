import Foundation

@MainActor
protocol MIDIPracticeStepMatchingProtocol: AnyObject {
    func reset(stepIndex: Int, expectedNotes: [PracticeStepNote])
    func register(_ observation: PerformanceObservation) -> StepAttemptMatchResult?
}

@MainActor
final class MIDIPracticeStepMatcher: MIDIPracticeStepMatchingProtocol {
    struct Configuration: Equatable {
        var simultaneousOnsetSpread: TimeInterval = 0.08
        var rolledOnsetSpan: TimeInterval = 0.55
    }

    private struct NoteIdentity: Hashable {
        let sourceKind: PerformanceObservation.Source.Kind
        let sourceID: String
        let channel: Int?
        let group: Int?
        let note: Int
    }

    private(set) var configuration: Configuration
    private let chordAccumulator: ChordAttemptAccumulator

    private var expectedUnion: Set<Int> = []
    private var onsetExpectation: ChordOnsetExpectation = .simultaneous
    private var heldNotes: Set<NoteIdentity> = []
    private var releaseRequiredBeforeOnset: Set<NoteIdentity> = []

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
        chordAccumulator = ChordAttemptAccumulator(
            windowSeconds: configuration.rolledOnsetSpan,
            simultaneousSpreadSeconds: configuration.simultaneousOnsetSpread
        )
    }

    func reset(stepIndex: Int, expectedNotes: [PracticeStepNote]) {
        guard stepIndex >= 0 else {
            expectedUnion.removeAll(keepingCapacity: true)
            heldNotes.removeAll(keepingCapacity: true)
            releaseRequiredBeforeOnset.removeAll(keepingCapacity: true)
            chordAccumulator.reset()
            return
        }

        let previousExpected = expectedUnion
        expectedUnion = Set(expectedNotes.map(\.midiNote))
        let repeatedNotes = previousExpected.intersection(expectedUnion)
        releaseRequiredBeforeOnset = heldNotes.filter { repeatedNotes.contains($0.note) }
        onsetExpectation = Set(expectedNotes.map(\.onTickOffset)).count > 1 ? .rolled : .simultaneous
        chordAccumulator.reset()
    }

    func register(_ observation: PerformanceObservation) -> StepAttemptMatchResult? {
        switch observation.event {
        case let .noteOn(note, _):
            return registerNoteOn(note: note, observation: observation)
        case let .noteOff(note, _):
            let identity = noteIdentity(note: note, observation: observation)
            heldNotes.remove(identity)
            releaseRequiredBeforeOnset.remove(identity)
            return nil
        default:
            return nil
        }
    }

    private func registerNoteOn(
        note: Int,
        observation: PerformanceObservation
    ) -> StepAttemptMatchResult {
        guard expectedUnion.isEmpty == false else { return .insufficientEvidence }
        let identity = noteIdentity(note: note, observation: observation)
        if observation.source.capabilities.release == .observed,
           releaseRequiredBeforeOnset.contains(identity)
        {
            return .insufficientEvidence
        }
        heldNotes.insert(identity)

        guard expectedUnion.contains(note) else {
            chordAccumulator.reset()
            return .wrongNote
        }
        return chordAccumulator.register(
            pressedNotes: [note],
            expectedNotes: expectedUnion.sorted(),
            tolerance: 0,
            onsetExpectation: onsetExpectation,
            at: observation.timing.correctedHost
        )
    }

    private func noteIdentity(
        note: Int,
        observation: PerformanceObservation
    ) -> NoteIdentity {
        NoteIdentity(
            sourceKind: observation.source.kind,
            sourceID: observation.source.id,
            channel: observation.channel,
            group: observation.group,
            note: note
        )
    }
}
