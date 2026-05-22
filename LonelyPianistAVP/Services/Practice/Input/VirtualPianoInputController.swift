import Foundation
import simd

@MainActor
protocol KeyContactDetectingProtocol: AnyObject {
    func reset()
    func detect(
        fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry
    ) -> KeyContactResult
}

extension KeyContactDetectionService: KeyContactDetectingProtocol {}
extension RealPianoContactDetectionService: KeyContactDetectingProtocol {}

@MainActor
final class VirtualPianoInputController: PracticeSessionLifecycleProtocol {
    private let detector: any KeyContactDetectingProtocol
    private let sequencerPlaybackService: PracticeSequencerPlaybackServiceProtocol
    private let stateStore: PracticeSessionStateStore
    private let handGateController: PracticeHandGateController
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
        sequencerPlaybackService.stopAllLiveNotes()
        detector.reset()
        stateStore.latestKeyContactResult = KeyContactResult(down: [], started: [], ended: [])
        stateStore.pressedNotes.removeAll()
        stateStore.latestNoteOnMIDINotes.removeAll()
    }

    func handleFingerTips(
        _ fingerTips: [String: SIMD3<Float>],
        keyboardGeometry: PianoKeyboardGeometry,
        at timestamp: Date,
        practiceHandMode: PracticeHandMode
    ) -> Set<Int> {
        let result = detector.detect(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry
        )
        stateStore.latestKeyContactResult = result
        stateStore.latestNoteOnMIDINotes = result.started

        let shouldPlayLiveNotes = stateStore.autoplayState == .off && stateStore.isManualReplayPlaying == false
        if shouldPlayLiveNotes {
            if result.started.isEmpty == false {
                try? sequencerPlaybackService.startLiveNotes(midiNotes: result.started)
            }
            if result.ended.isEmpty == false {
                sequencerPlaybackService.stopLiveNotes(midiNotes: result.ended)
            }
        }

        stateStore.pressedNotes = result.down
        handGateController.updateHandGateState(
            fingerTips: fingerTips,
            keyboardGeometry: keyboardGeometry,
            exactPressedNotes: result.down
        )

        if result.started.isEmpty == false {
            handGateController.registerChordAttemptIfNeeded(
                pressedNotes: result.started,
                at: timestamp,
                practiceHandMode: practiceHandMode
            )
        }

        return result.down
    }
}
