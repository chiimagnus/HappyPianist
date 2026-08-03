import Diagnostics
import Foundation
import MusicXML
@testable import Practice
import Testing

@MainActor
@Test
func roundSessionOwnsPreparationContextCompletionAndFeedback() async throws {
    let prepared = try await makeRoundSessionPreparedPractice()
    let controller = PracticeRoundSessionController(
        settingsProvider: RoundSessionSettingsProvider(),
        defaultsStore: RoundSessionDefaultsStore()
    )

    let installation = try controller.install(preparedPractice: prepared, restoredProgress: nil)

    #expect(controller.state.notationProjection != nil)
    #expect(controller.state.attributeTimeline != nil)
    #expect(controller.state.activeRange == installation.activeRange)
    #expect(controller.state.currentStepIndex == installation.activeRange.firstStepIndex)

    guard case let .guiding(currentStepIndex, _) = controller.advance() else {
        Issue.record("Expected the second step to remain in the shared round")
        return
    }
    #expect(currentStepIndex == 1)
    #expect(controller.advance() == .completed(waitingForAssessment: true))
    #expect(await controller.completePassageAnalysis(
        assessment: nil,
        analyzerRoundGeneration: 1
    ) == .completed(waitingForAssessment: false))
    #expect(controller.state.latestFeedbackEvent?.kind == .roundSummaryReady)
}

@MainActor
@Test
func roundSessionWaitsForAssessmentBeforeRestartingALoop() async throws {
    let prepared = try await makeRoundSessionPreparedPractice()
    let controller = PracticeRoundSessionController(
        settingsProvider: RoundSessionSettingsProvider(),
        defaultsStore: RoundSessionDefaultsStore()
    )
    _ = try controller.install(preparedPractice: prepared, restoredProgress: nil)
    let passage = try #require(PracticePassage(
        start: prepared.measureSpans[0].occurrenceID,
        end: prepared.measureSpans[1].occurrenceID
    ))
    controller.roundConfigurationController.pendingPassage = passage
    controller.roundConfigurationController.pendingLoopEnabled = true
    _ = try controller.applyPendingConfiguration()

    _ = controller.advance()
    #expect(controller.advance() == .completed(waitingForAssessment: true))
    guard case let .guiding(currentStepIndex, _) = await controller.completePassageAnalysis(
        assessment: nil,
        analyzerRoundGeneration: 1
    ) else {
        Issue.record("Expected the completed loop to restart only after analysis")
        return
    }
    #expect(currentStepIndex == 0)
    #expect(controller.state.state == .guiding(stepIndex: 0))
}

@MainActor
@Test
func roundSessionStagesTheSingleCoachingActionFromAssessment() async throws {
    let prepared = try await makeRoundSessionPreparedPractice()
    let controller = PracticeRoundSessionController(
        settingsProvider: RoundSessionSettingsProvider(),
        defaultsStore: RoundSessionDefaultsStore()
    )
    let installation = try controller.install(preparedPractice: prepared, restoredProgress: nil)
    let pitch = PerformanceAssessmentDimensionResult(
        dimension: .exactPitch,
        outcome: .incorrect,
        evidenceStatus: .observed,
        sampleCount: 1,
        confidence: 0.9,
        evidence: []
    )
    let assessment = PassagePerformanceAssessment(
        planID: prepared.performancePlan.id,
        sourceGeneration: 1,
        tickRange: installation.activeRange.tickRange,
        rubricVersion: .capabilityAware,
        dimensions: [pitch],
        measures: [MeasurePerformanceAssessment(
            occurrenceID: prepared.measureSpans[0].occurrenceID,
            tickRange: prepared.measureSpans[0].startTick ..< prepared.measureSpans[0].endTick,
            dimensions: [pitch]
        )]
    )

    _ = controller.advance()
    _ = controller.advance()
    _ = await controller.completePassageAnalysis(
        assessment: assessment,
        analyzerRoundGeneration: 1
    )

    #expect(controller.state.currentCoachingDecision?.action.kind == .pitchAccuracy)
    #expect(controller.stageCurrentCoachingRound())
    #expect(controller.roundConfigurationController.pendingTempoScale == 0.7)
}

private func makeRoundSessionPreparedPractice() async throws -> PreparedPractice {
    let url = FileManager.default.temporaryDirectory.appending(path: "round-session-\(UUID().uuidString).musicxml")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(roundSessionFixture.utf8).write(to: url)
    return try await PracticePreparationService(
        diagnosticsReporter: RoundSessionDiagnosticsReporter()
    ).prepare(
        songID: UUID(),
        from: url,
        file: ImportedMusicXMLFile(fileName: "Round Session", storedURL: url, importedAt: .now),
        options: .practice
    )
}

private let roundSessionFixture = """
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1"><attributes><divisions>1</divisions></attributes><note><pitch><step>C</step><octave>3</octave></pitch><duration>1</duration><type>quarter</type></note></measure>
    <measure number="2"><note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><type>quarter</type></note></measure>
  </part>
</score-partwise>
"""

private struct RoundSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode = .step
    let practiceHandMode: PracticeHandMode = .both
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private final class RoundSessionDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    let tempoScale = 1.0
    let loopEnabled = false
    let requiredSuccesses = 1

    func save(
        handMode _: PracticeHandMode,
        manualAdvanceMode _: ManualAdvanceMode,
        soundRoutingSettings _: PracticeSoundRoutingSettings,
        tempoScale _: Double,
        loopEnabled _: Bool,
        requiredSuccesses _: Int
    ) {}
}

private actor RoundSessionDiagnosticsReporter: DiagnosticsReporting {
    func record(_: DiagnosticEvent) -> DiagnosticRecordResult {
        DiagnosticRecordResult(persistedForExport: false)
    }
}
