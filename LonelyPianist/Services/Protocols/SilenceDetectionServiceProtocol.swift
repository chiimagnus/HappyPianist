import Foundation

protocol SilenceDetectionServiceProtocol {
    var timeoutSeconds: TimeInterval { get set }

    func reset()
    func handle(event: MIDIEvent)
    func pollSilenceDetected() -> Bool
}

