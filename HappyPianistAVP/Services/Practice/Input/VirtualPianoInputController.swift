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
        let transportNoteOns = activeMIDINotes.subtracting(stateStore.pressedNotes)
        let transportNoteOffs = stateStore.pressedNotes.subtracting(activeMIDINotes)
        stateStore.latestNoteOnMIDINotes = startedMIDINotes

        let shouldPlayLiveNotes = stateStore.autoplayState == .off && stateStore.isManualReplayPlaying == false
        if shouldPlayLiveNotes {
            enqueuePlayback(
                commands: transportNoteOffs.sorted().map {
                    PracticePlaybackCommand(
                        sourceEventID: "virtual-piano-\($0)",
                        kind: .noteOff(midi: $0)
                    )
                } + transportNoteOns.sorted().map {
                    PracticePlaybackCommand(
                        sourceEventID: "virtual-piano-\($0)",
                        kind: .noteOn(midi: $0, velocity: 96)
                    )
                }
            )
        }

        stateStore.pressedNotes = activeMIDINotes
        handGateController.updateHandGateState(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: activeMIDINotes
        )

        if startedMIDINotes.isEmpty == false {
            handGateController.registerChordAttemptIfNeeded(
                pressedNotes: startedMIDINotes,
                at: timestamp,
                practiceHandMode: practiceHandMode
            )
        }

        return activeMIDINotes
    }

    func waitForPendingPlayback() async {
        await playbackTask?.value
    }

    private func enqueuePlayback(commands: [PracticePlaybackCommand]) {
        guard commands.isEmpty == false else { return }
        let previousPlaybackTask = playbackTask
        let sequencerPlaybackService = sequencerPlaybackService
        playbackTask = Task {
            await previousPlaybackTask?.value
            do {
                try await sequencerPlaybackService.execute(commands: commands)
            } catch {
                stateStore.recordPlaybackError(error)
            }
        }
    }
}
