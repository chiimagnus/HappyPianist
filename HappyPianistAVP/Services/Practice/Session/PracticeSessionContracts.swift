import Foundation
import MIDI
import MusicXML

struct PracticePreparationOptions: Equatable {
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
