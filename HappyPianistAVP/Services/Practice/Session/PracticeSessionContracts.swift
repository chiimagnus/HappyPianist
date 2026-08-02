import Foundation
import MIDI

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
