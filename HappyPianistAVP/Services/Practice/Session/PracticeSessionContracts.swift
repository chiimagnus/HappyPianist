import Foundation
import MIDI
import Practice

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
