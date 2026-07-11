import Foundation

@MainActor
final class PracticeHighlightGuideController: PracticeSessionLifecycleProtocol {
    private let sleeper: SleeperProtocol
    private let stateStore: PracticeSessionStateStore

    private var transitionTask: Task<Void, Never>?
    private var hasShutdown = false

    init(
        sleeper: SleeperProtocol,
        stateStore: PracticeSessionStateStore
    ) {
        self.sleeper = sleeper
        self.stateStore = stateStore
    }

    func shutdown() {
        guard hasShutdown == false else { return }
        hasShutdown = true
        stopTransition()
    }

    func stopTransition() {
        transitionTask?.cancel()
        transitionTask = nil
    }

    func setCurrentHighlightGuideForStepIndex(_ stepIndex: Int) {
        stopTransition()

        guard stateStore.steps.indices.contains(stepIndex),
              stateStore.activeRange?.contains(stepIndex: stepIndex) ?? true
        else {
            stateStore.currentHighlightGuideIndex = nil
            return
        }
        stateStore.currentHighlightGuideIndex = stateStore.strictTriggerGuideIndex(forStepIndex: stepIndex)
    }

    func updateHighlightGuideAfterStepAdvance(previousTick: Int, nextStepIndex: Int) {
        if stateStore.autoplayState != .off {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }

        stopTransition()

        guard stateStore.steps.indices.contains(nextStepIndex),
              stateStore.activeRange?.contains(stepIndex: nextStepIndex) ?? true
        else {
            stateStore.currentHighlightGuideIndex = nil
            return
        }

        let nextTick = stateStore.steps[nextStepIndex].tick
        let transitionIndex = stateStore.highlightGuides.firstIndex { guide in
            guide.tick > previousTick &&
                guide.tick < nextTick &&
                (stateStore.activeRange?.contains(tick: guide.tick) ?? true) &&
                (guide.kind == .release || guide.kind == .gap)
        }

        guard let transitionIndex else {
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            return
        }

        stateStore.currentHighlightGuideIndex = transitionIndex
        transitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await sleeper.sleep(for: .seconds(0.12))
            guard Task.isCancelled == false else { return }
            setCurrentHighlightGuideForStepIndex(nextStepIndex)
            transitionTask = nil
        }
    }
}
