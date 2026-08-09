import Foundation

public struct PracticeSequencerSequence: Sendable {
    public let midiData: Data
    public let durationSeconds: TimeInterval
    public let events: [PracticeSequencerMIDIEvent]
    public let outputApproximations: [PerformanceOutputApproximation]

    public init(
        midiData: Data,
        durationSeconds: TimeInterval,
        events: [PracticeSequencerMIDIEvent],
        outputApproximations: [PerformanceOutputApproximation] = []
    ) {
        self.midiData = midiData
        self.durationSeconds = durationSeconds
        self.events = events
        self.outputApproximations = outputApproximations
    }
}

public struct PracticePlaybackCommand: Equatable, Sendable {
    public let sourceEventID: String
    public let kind: PracticeSequencerMIDIEvent.Kind

    public init(sourceEventID: String, kind: PracticeSequencerMIDIEvent.Kind) {
        self.sourceEventID = sourceEventID
        self.kind = kind
    }
}

public enum PracticePlaybackRateError: Error, Equatable, Sendable {
    case invalidRate
}

public protocol PracticeSequencerPlaybackServiceProtocol: AnyObject, Sendable {
    func warmUp() async throws
    func stop(resetCommands: [PerformanceTransportCommand]) async
    func load(sequence: PracticeSequencerSequence) async throws
    func play(fromSeconds start: TimeInterval) async throws
    func pause() async
    func resume() async throws
    func setPlaybackRate(_ rate: Double) async throws
    func currentSeconds() async -> TimeInterval
    func playOneShot(commands: [PracticePlaybackCommand], durationSeconds: TimeInterval) async throws
    func execute(commands: [PracticePlaybackCommand]) async throws
    func stopAllLiveNotes() async
}
