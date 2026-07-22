import Foundation

struct PracticePreparationOptions: Equatable, Sendable {
    let scoreOrder: MusicXMLScoreOrder

    static let practice = PracticePreparationOptions(
        scoreOrder: MusicXMLRealisticPlaybackDefaults.practiceScoreOrder
    )
    static let referencePlayback = PracticePreparationOptions(
        scoreOrder: MusicXMLRealisticPlaybackDefaults.referencePlaybackScoreOrder
    )
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

@MainActor
protocol PerformanceObservationStreamProviding: AnyObject {
    var capabilities: PerformanceInputCapabilities { get }
    func performanceObservationsStream() -> AsyncStream<PerformanceObservation>
}

enum PracticeSessionEffect: Equatable {
    case attemptEvaluated(StepAttemptMatchResult)
    case advanceToNextStep
    case refreshPracticeInput
    case refreshAudioRecognition
    case stopTransientWork
    case stopAudioRecognition
    case stopPracticeInput
    case inputCapabilitiesAvailable(PerformanceInputCapabilities)
}

enum PracticeImmersiveOpenResult: Equatable {
    case opened
    case userCancelled
    case error
    case unknown
}

typealias PracticeImmersiveOpenHandler =
    @MainActor @Sendable (String) async -> PracticeImmersiveOpenResult
typealias PracticeImmersiveDismissHandler = @MainActor @Sendable () async -> Void
