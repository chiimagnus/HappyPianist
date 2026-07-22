@testable import HappyPianistAVP
import Testing

@Test
func improvScheduleBuilderSortsAndGeneratesNoteOff() {
    let notes = [
        ImprovDialogueNote(note: 64, velocity: 90, time: 0.4, duration: 0.2),
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: 0.1),
        ImprovDialogueNote(note: 67, velocity: 90, time: 0.2, duration: 0.1),
    ]

    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 6)
    #expect(abs(schedule[0].timeSeconds - 0.0) < 0.0001)
    // A.I. Duet: reply note durations are shortened to 90% (see `ImprovScheduleBuilder`).
    #expect(abs(schedule[5].timeSeconds - 0.58) < 0.0001)
}

@Test
func improvScheduleBuilderClampsDuration() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 90, time: 0.0, duration: -1.0),
    ]
    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 2)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(schedule[1].timeSeconds >= 0.05)
}

@Test
func improvScheduleBuilderNegativeTimeStillProducesDuration() {
    let notes = [
        ImprovDialogueNote(note: 60, velocity: 90, time: -1.0, duration: 0.2),
    ]
    let builder = ImprovScheduleBuilder()
    let schedule = builder.buildSchedule(from: notes, leadInSeconds: 0)
    #expect(schedule.count == 2)
    #expect(schedule[0].timeSeconds == 0.0)
    #expect(schedule[1].timeSeconds >= 0.18)
}

@Test
func improvScheduleBuilderEmptyNotesIsEmptySchedule() {
    let builder = ImprovScheduleBuilder()
    #expect(builder.buildSchedule(from: [ImprovDialogueNote](), leadInSeconds: 0).isEmpty)
}

@Test
func improvScheduleBuilderRuleAndNetworkQualityCorpusUseTheSharedGate() {
    let builder = ImprovScheduleBuilder()
    let rubric = ImprovQualityRubric()

    let rule = DuetQualityRegressionFixtures.ruleQualityCorpus
    #expect(rule.provider == .localRule)
    #expect(rule.parameters.seed == .some(rule.seed))
    #expect(rule.parameters.strategy == "deterministic")
    guard case .generatedRule = rule.response else {
        Issue.record("Rule corpus must generate from its fixed seed.")
        return
    }

    let ruleNotes = RuleImprovGenerator().generateRuleResponse(
        notes: rule.promptNotes,
        params: rule.parameters,
        sessionID: nil,
        seed: rule.seed
    )
    let ruleSchedule = builder.buildSchedule(from: ruleNotes, leadInSeconds: 0)
    #expect(ruleSchedule.isEmpty == false)
    #expect(rubric.assess(ruleSchedule).band == rule.expectedBand)

    let network = DuetQualityRegressionFixtures.networkFakeQualityCorpus
    #expect(network.provider == .networkBonjourHTTPAriaV2)
    #expect(network.parameters.seed == .some(network.seed))
    #expect(network.parameters.strategy == "network")
    guard case let .networkFakeEvents(events) = network.response else {
        Issue.record("Network corpus must use a protocol response fake.")
        return
    }

    let networkSchedule = builder.buildSchedule(from: events, leadInSeconds: 0)
    #expect(networkSchedule.isEmpty == false)
    #expect(rubric.assess(networkSchedule).band == network.expectedBand)
}
