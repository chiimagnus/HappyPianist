import Observation

@MainActor
@Observable
final class PracticeFeedbackViewModel {
    private let sleeper: any SleeperProtocol
    private var dismissalTask: Task<Void, Never>?
    private(set) var cue: PracticeFeedbackEvent?

    init(sleeper: any SleeperProtocol = TaskSleeper()) {
        self.sleeper = sleeper
    }

    func present(_ event: PracticeFeedbackEvent?) {
        dismissalTask?.cancel()
        guard let event else {
            cue = nil
            return
        }
        cue = event
        dismissalTask = Task { [weak self, sleeper] in
            try? await sleeper.sleep(for: .seconds(3))
            guard Task.isCancelled == false else { return }
            self?.cue = nil
        }
    }

    func cancel() {
        dismissalTask?.cancel()
        dismissalTask = nil
        cue = nil
    }
}
