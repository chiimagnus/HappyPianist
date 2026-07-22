import Foundation
import Observation

@MainActor
@Observable
final class PracticeFeedbackViewModel {
    private let sleeper: any SleeperProtocol
    private var dismissalTask: Task<Void, Never>?
    private(set) var cue: PracticeFeedbackEvent?
    private(set) var coachingPresentation: PracticeCoachingPresentation?

    init(sleeper: any SleeperProtocol = TaskSleeper()) {
        self.sleeper = sleeper
    }

    func present(
        _ event: PracticeFeedbackEvent?,
        coachingDecision: CoachingDecision? = nil
    ) {
        dismissalTask?.cancel()
        guard let event else {
            cue = nil
            coachingPresentation = nil
            return
        }
        cue = event
        coachingPresentation = coachingDecision.map(PracticeCoachingPresentation.init)
        dismissalTask = Task { [weak self, sleeper] in
            try? await sleeper.sleep(for: .seconds(3))
            guard Task.isCancelled == false else { return }
            self?.cue = nil
            self?.coachingPresentation = nil
        }
    }

    func cancel() {
        dismissalTask?.cancel()
        dismissalTask = nil
        cue = nil
        coachingPresentation = nil
    }

}
