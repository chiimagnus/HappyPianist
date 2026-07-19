import Foundation
import simd

@MainActor
protocol KeyContactDetectingProtocol: AnyObject {
    func reset()
    func detect(
        fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry,
        at timestamp: PerformanceMonotonicInstant
    ) -> [PianoKeyContactObservation]
}

extension KeyContactDetectionService: KeyContactDetectingProtocol {}
extension RealPianoContactDetectionService: KeyContactDetectingProtocol {}

@MainActor
final class VirtualPianoInputController {
    private let detector: any KeyContactDetectingProtocol
    private let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    private let stateStore: PracticeSessionStateStore
    private let handGateController: PracticeHandGateController
    private var playbackTask: Task<Void, Never>?
    private var soundingContactByMIDINote: [Int: PianoKeyContactID] = [:]
    private var hasShutdown = false

    init(
        detector: any KeyContactDetectingProtocol,
        sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol,
        stateStore: PracticeSessionStateStore,
        handGateController: PracticeHandGateController
    ) {
        self.detector = detector
        self.sequencerPlaybackService = sequencerPlaybackService
        self.stateStore = stateStore
        self.handGateController = handGateController
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stop()
    }

    func stop() {
        let previousPlaybackTask = playbackTask
        let sequencerPlaybackService = sequencerPlaybackService
        playbackTask = Task {
            await previousPlaybackTask?.value
            await sequencerPlaybackService.stopAllLiveNotes()
        }
        detector.reset()
        stateStore.latestKeyContactObservations = []
        stateStore.pressedNotes.removeAll()
        stateStore.latestNoteOnMIDINotes.removeAll()
        soundingContactByMIDINote.removeAll()
    }

    func handleFingerTips(
        _ fingerTips: FingerTipsSnapshot,
        keyboardGeometry: PianoKeyboardGeometry,
        at timestamp: PerformanceMonotonicInstant,
        practiceHandMode: PracticeHandMode
    ) -> Set<Int> {
        let result = detector.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            at: timestamp
        )
        stateStore.latestKeyContactObservations = result
        let activeMIDINotes = result.activeMIDINotes
        let startedMIDINotes = result.startedMIDINotes
        stateStore.latestNoteOnMIDINotes = startedMIDINotes

        let shouldPlayLiveNotes = stateStore.autoplayState == .off && stateStore.isManualReplayPlaying == false
        let liveNoteEvents = transportEvents(
            from: result,
            activeMIDINotes: activeMIDINotes,
            at: timestamp,
            allowsNoteOn: shouldPlayLiveNotes
        )
        if liveNoteEvents.isEmpty == false {
            enqueuePlayback(liveNoteEvents: liveNoteEvents)
        }

        stateStore.pressedNotes = activeMIDINotes
        handGateController.updateHandGateState(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: activeMIDINotes,
            at: timestamp
        )

        handGateController.registerChordAttemptIfNeeded(
            observations: result,
            at: timestamp,
            practiceHandMode: practiceHandMode
        )

        return activeMIDINotes
    }

    func waitForPendingPlayback() async {
        await playbackTask?.value
    }

    private func transportEvents(
        from observations: [PianoKeyContactObservation],
        activeMIDINotes: Set<Int>,
        at timestamp: PerformanceMonotonicInstant,
        allowsNoteOn: Bool
    ) -> [PracticeLiveNoteEvent] {
        var events: [PracticeLiveNoteEvent] = []
        let endedByMIDI = Dictionary(
            observations.lazy.compactMap { observation -> (Int, PianoKeyContactObservation)? in
                guard observation.phase == .ended,
                      let midiNote = observation.keyCandidate.exactMIDINote
                else { return nil }
                return (midiNote, observation)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for midiNote in soundingContactByMIDINote.keys.sorted()
        where allowsNoteOn == false || activeMIDINotes.contains(midiNote) == false {
            guard let contactID = soundingContactByMIDINote.removeValue(forKey: midiNote) else { continue }
            events.append(
                PracticeLiveNoteEvent(
                    contactID: contactID,
                    midiNote: midiNote,
                    phase: .noteOff,
                    timestamp: endedByMIDI[midiNote]?.timestamp ?? timestamp
                )
            )
        }

        guard allowsNoteOn else { return events }
        for (midiNote, observation) in endedByMIDI.sorted(by: { $0.key < $1.key })
        where activeMIDINotes.contains(midiNote) == false
            && events.contains(where: { $0.midiNote == midiNote && $0.phase == .noteOff }) == false {
            events.append(
                PracticeLiveNoteEvent(
                    contactID: observation.id,
                    midiNote: midiNote,
                    phase: .noteOff,
                    timestamp: observation.timestamp
                )
            )
        }

        let startsByMIDI = Dictionary(
            observations.lazy.compactMap { observation -> (Int, PianoKeyContactObservation)? in
                guard observation.phase == .started,
                      let midiNote = observation.keyCandidate.exactMIDINote,
                      observation.resolvedVelocity != nil
                else { return nil }
                return (midiNote, observation)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for midiNote in activeMIDINotes.sorted() where soundingContactByMIDINote[midiNote] == nil {
            guard let observation = startsByMIDI[midiNote],
                  let velocity = observation.resolvedVelocity
            else { continue }
            soundingContactByMIDINote[midiNote] = observation.id
            events.append(
                PracticeLiveNoteEvent(
                    contactID: observation.id,
                    midiNote: midiNote,
                    phase: .noteOn(velocity: velocity),
                    timestamp: observation.timestamp
                )
            )
        }
        return events
    }

    private func enqueuePlayback(liveNoteEvents: [PracticeLiveNoteEvent]) {
        let previousPlaybackTask = playbackTask
        let sequencerPlaybackService = sequencerPlaybackService
        playbackTask = Task {
            await previousPlaybackTask?.value
            do {
                try await sequencerPlaybackService.execute(liveNoteEvents: liveNoteEvents)
            } catch {
                stateStore.recordPlaybackError(error)
            }
        }
    }
}
