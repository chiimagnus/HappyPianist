@testable import HappyPianistAVP

func ruleBasedCompanionDecisionTestRegistry() -> CompanionDecisionBackendRegistry {
    CompanionDecisionBackendRegistry(backends: [RuleBasedCompanionDecisionBackend()])
}
