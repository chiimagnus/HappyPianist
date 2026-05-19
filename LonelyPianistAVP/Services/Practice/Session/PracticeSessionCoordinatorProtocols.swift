import Foundation

protocol PracticeMIDIInputCoordinating: AnyObject {
    func refreshForCurrentState()
    func stop()
}

protocol PracticeAudioRecognitionCoordinating: AnyObject {
    func refreshForCurrentState()
    func stop()
}

protocol PracticePlaybackCoordinating: AnyObject {
    func stopTransientWork()
    func playCurrentStepSound(applyRecognitionSuppress: Bool)
}

@MainActor
protocol PracticeSessionEffectHandling: AnyObject {
    func handle(effect: PracticeSessionEffect)
}
