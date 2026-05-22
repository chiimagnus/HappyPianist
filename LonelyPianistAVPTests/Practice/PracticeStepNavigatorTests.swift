@testable import LonelyPianistAVP
import Testing

@Test
func advanceWithEmptyStepsStaysIdle() {
    let navigator = PracticeStepNavigator()
    #expect(navigator.advance(steps: [], currentStepIndex: 0) == .init(state: .idle, currentStepIndex: 0))
}

@Test
func advanceFromLastStepCompletes() {
    let navigator = PracticeStepNavigator()
    let steps = [PracticeStep(tick: 0, notes: []), PracticeStep(tick: 1, notes: [])]

    #expect(
        navigator.advance(steps: steps, currentStepIndex: 1) ==
            .init(state: .completed, currentStepIndex: 2)
    )
}

@Test
func repeatedAdvanceEventuallyCompletes() {
    let navigator = PracticeStepNavigator()
    let steps = [PracticeStep(tick: 0, notes: []), PracticeStep(tick: 1, notes: [])]

    var navigation = navigator.restart(steps: steps)
    #expect(navigation == .init(state: .guiding(stepIndex: 0), currentStepIndex: 0))

    navigation = navigator.advance(steps: steps, currentStepIndex: navigation.currentStepIndex)
    #expect(navigation == .init(state: .guiding(stepIndex: 1), currentStepIndex: 1))

    navigation = navigator.advance(steps: steps, currentStepIndex: navigation.currentStepIndex)
    #expect(navigation == .init(state: .completed, currentStepIndex: 2))
}

@Test
func moveToInvalidIndexCompletes() {
    let navigator = PracticeStepNavigator()
    let steps = [PracticeStep(tick: 0, notes: [])]

    #expect(navigator.move(to: 999, steps: steps) == .init(state: .completed, currentStepIndex: 1))
}
