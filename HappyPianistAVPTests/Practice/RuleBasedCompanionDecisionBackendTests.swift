import Foundation
import Practice
import MusicXML
import Diagnostics
@testable import HappyPianistAVP
import Testing

@Test
func ruleBasedCompanionDecisionBackendYieldsForDenseHeldTexture() async throws {
    let backend = RuleBasedCompanionDecisionBackend()
    let decision = try await backend.decide(
        .init(
            nowTimestampSeconds: 10.0,
            heldNotesCount: 2,
            sustainValue: 0,
            recentIOIMedianSeconds: 0.12,
            recentVelocityTrend: 2,
            recentNoteDensityPerSecond: 3.0,
            lastUserEventTimestampSeconds: 9.8,
            lastNoteOnTimestampSeconds: 9.9,
            activePitchCenter: 64,
            isAIPlaybackActive: false
        )
    )

    #expect(decision.action == .yield)
    #expect(decision.shouldRequestGeneration == false)
    #expect(decision.shouldClearFutureWindows)
}

@Test
func ruleBasedCompanionDecisionBackendYieldsForDenseStaccatoTexture() async throws {
    let backend = RuleBasedCompanionDecisionBackend()
    let decision = try await backend.decide(
        .init(
            nowTimestampSeconds: 10,
            heldNotesCount: 0,
            sustainValue: 0,
            recentIOIMedianSeconds: 0.12,
            recentVelocityTrend: 0,
            recentNoteDensityPerSecond: 3,
            lastUserEventTimestampSeconds: 9.9,
            lastNoteOnTimestampSeconds: 9.8,
            activePitchCenter: 64,
            isAIPlaybackActive: false
        )
    )

    #expect(decision.action == .yield)
    #expect(decision.shouldClearFutureWindows)
}

@Test
func ruleBasedCompanionDecisionBackendUsesSparseActionForSustainLedHeldTexture() async throws {
    let backend = RuleBasedCompanionDecisionBackend()
    let decision = try await backend.decide(
        .init(
            nowTimestampSeconds: 5.0,
            heldNotesCount: 1,
            sustainValue: 127,
            recentIOIMedianSeconds: 0.32,
            recentVelocityTrend: 8,
            recentNoteDensityPerSecond: 1.0,
            lastUserEventTimestampSeconds: 4.9,
            lastNoteOnTimestampSeconds: 4.85,
            activePitchCenter: 60,
            isAIPlaybackActive: false
        )
    )

    #expect(decision.action == .sparse)
    #expect(decision.shouldRequestGeneration)
    #expect(decision.shouldClearFutureWindows == false)
}

@Test
func ruleBasedCompanionDecisionBackendSupportsRecentHeldLine() async throws {
    let backend = RuleBasedCompanionDecisionBackend()
    let decision = try await backend.decide(
        .init(
            nowTimestampSeconds: 20.0,
            heldNotesCount: 1,
            sustainValue: 0,
            recentIOIMedianSeconds: 0.28,
            recentVelocityTrend: 0,
            recentNoteDensityPerSecond: 1.4,
            lastUserEventTimestampSeconds: 19.7,
            lastNoteOnTimestampSeconds: 19.8,
            activePitchCenter: 67,
            isAIPlaybackActive: false
        )
    )

    #expect(decision.action == .support)
    #expect(decision.shouldRequestGeneration)
    #expect(decision.shouldClearFutureWindows == false)
}

@Test
func ruleBasedCompanionDecisionBackendListensForStaleInput() async throws {
    let backend = RuleBasedCompanionDecisionBackend()
    let decision = try await backend.decide(
        .init(
            nowTimestampSeconds: 100.0,
            heldNotesCount: 0,
            sustainValue: 0,
            recentIOIMedianSeconds: nil,
            recentVelocityTrend: 0,
            recentNoteDensityPerSecond: 0,
            lastUserEventTimestampSeconds: 98.0,
            lastNoteOnTimestampSeconds: 98.0,
            activePitchCenter: nil,
            isAIPlaybackActive: false
        )
    )

    #expect(decision.action == .listen)
    #expect(decision.shouldRequestGeneration == false)
    #expect(decision.shouldClearFutureWindows)
}


@Test
func companionDecisionSemanticActionsDeriveGenerationAndClearing() {
    let listen = CompanionDecision(action: .listen)
    #expect(listen.shouldRequestGeneration == false)
    #expect(listen.shouldClearFutureWindows)

    let respond = CompanionDecision(action: .respond)
    #expect(respond.shouldRequestGeneration)
    #expect(respond.shouldClearFutureWindows == false)
}


@Test
func companionDecisionBackendSelectionDefaultsToRulesAndRejectsUnknownStoredValue() {
    let suiteName = "CompanionDecisionBackendSelectionTests-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Unable to create isolated user defaults.")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let selection = CompanionDecisionBackendSelection(userDefaults: defaults)
    #expect(selection.selectedKind() == .ruleBased)

    defaults.set(
        CompanionDecisionBackendKind.networkBonjourQwen.rawValue,
        forKey: CompanionDecisionBackendSelection.userDefaultsKey
    )
    #expect(selection.selectedKind() == .networkBonjourQwen)

    defaults.set(
        "removed_decision_backend",
        forKey: CompanionDecisionBackendSelection.userDefaultsKey
    )
    #expect(selection.selectedKind() == nil)
}

@Test
func companionDecisionBackendRegistryDoesNotFallbackWhenSelectedBackendIsUnavailable() throws {
    let registry = CompanionDecisionBackendRegistry(
        backends: [RuleBasedCompanionDecisionBackend()]
    )

    #expect(throws: CompanionDecisionBackendRegistryError.unavailable(.networkBonjourQwen)) {
        _ = try registry.backend(for: .networkBonjourQwen)
    }
}
