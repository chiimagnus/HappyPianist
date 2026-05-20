protocol PracticeAudioRecognitionInputServiceProtocol: AnyObject {
    func refreshForCurrentState()
    func stop()
    func shutdown()
}
