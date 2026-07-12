import Foundation

protocol PracticeSessionLifecycleProtocol: AnyObject {
    func shutdown()
}

protocol PracticeAudioRecognitionInputServiceProtocol: AnyObject {
    func refreshForCurrentState()
    func stop()
    func shutdown()
}

protocol PracticeMIDIInputServiceProtocol: AnyObject {
    func refreshForCurrentState()
    func stop()
    func shutdown()
}

protocol PracticePlaybackControlServiceProtocol: AnyObject {
    func startAutoplayTaskIfNeeded()
    func stopAutoplayTask()
    func stopAutoplayAudio()
}

@MainActor
protocol PracticeSessionEffectHandlerProtocol: AnyObject {
    func handle(effect: PracticeSessionEffect)
}

protocol PracticeInputEventSourceProtocol: AnyObject {
    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent>
    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent>

    func start() throws
    func stop()
}

enum PracticeSessionEffect: Equatable {
    case attemptEvaluated(StepAttemptMatchResult)
    case advanceToNextStep
    case refreshPracticeInput
    case refreshAudioRecognition
    case playCurrentStepSound(applyRecognitionSuppress: Bool)
    case stopTransientWork
    case stopAudioRecognition
    case stopPracticeInput
}

enum PracticeImmersiveOpenResult: Equatable {
    case opened
    case userCancelled
    case error
    case unknown
}

typealias PracticeImmersiveOpenHandler = @MainActor @Sendable (String) async -> PracticeImmersiveOpenResult
typealias PracticeImmersiveDismissHandler = @MainActor @Sendable () async -> Void
