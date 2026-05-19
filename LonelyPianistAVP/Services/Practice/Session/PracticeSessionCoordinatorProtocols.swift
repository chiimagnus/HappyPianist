import Foundation

protocol PracticeMIDIInputCoordinatorProtocol: AnyObject {
    func refreshForCurrentState()
    func stop()
}

protocol PracticeAudioRecognitionCoordinatorProtocol: AnyObject {
    func refreshForCurrentState()
    func stop()
}

protocol PracticePlaybackCoordinatorProtocol: AnyObject {
    func stopTransientWork()
    func playCurrentStepSound(applyRecognitionSuppress: Bool)
}

@MainActor
protocol PracticeSessionEffectHandlerProtocol: AnyObject {
    func handle(effect: PracticeSessionEffect)
}
