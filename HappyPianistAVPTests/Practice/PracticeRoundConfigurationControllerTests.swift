import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
struct PracticeRoundConfigurationControllerTests {
    @Test func pendingChangesDoNotMutateActiveRoundUntilApply() throws {
        let stateStore = PracticeSessionStateStore()
        let defaults = CapturingRoundDefaultsStore()
        let controller = PracticeRoundConfigurationController(
            stateStore: stateStore,
            settingsProvider: FixedPracticeSettingsProvider(),
            defaultsStore: defaults
        )
        let passage = try #require(makePassage())
        controller.installInitialPassageIfNeeded(passage)

        #expect(stateStore.activeRoundConfiguration?.handMode == .both)
        let initialGeneration = stateStore.roundGeneration

        controller.pendingHandMode = .right
        controller.pendingTempoScale = 0.65
        controller.pendingLoopEnabled = true
        controller.pendingRequiredSuccesses = 4

        #expect(stateStore.activeRoundConfiguration?.handMode == .both)
        #expect(stateStore.activeRoundConfiguration?.tempoScale == 1)
        #expect(stateStore.roundGeneration == initialGeneration)
        #expect(controller.hasPendingChanges)

        _ = controller.applyPending()

        #expect(stateStore.activeRoundConfiguration?.handMode == .right)
        #expect(stateStore.activeRoundConfiguration?.tempoScale == 0.65)
        #expect(stateStore.activeRoundConfiguration?.loopEnabled == true)
        #expect(stateStore.activeRoundConfiguration?.requiredSuccesses == 4)
        #expect(stateStore.roundGeneration == initialGeneration + 1)
        #expect(defaults.savedHandMode == .right)
    }

    @Test func routeChangeRequestsSessionRebuildOnlyWhenApplied() throws {
        let stateStore = PracticeSessionStateStore()
        let controller = PracticeRoundConfigurationController(
            stateStore: stateStore,
            settingsProvider: FixedPracticeSettingsProvider(),
            defaultsStore: CapturingRoundDefaultsStore()
        )
        controller.installInitialPassageIfNeeded(try #require(makePassage()))

        controller.pendingSoundOutputRoute = .externalMIDIDestination
        controller.pendingMIDIDestinationUniqueID = 42

        #expect(stateStore.activeSoundRoutingSettings.outputRoute == .localSampler)
        #expect(controller.applyPending())
        #expect(stateStore.activeSoundRoutingSettings.outputRoute == .externalMIDIDestination)
        #expect(stateStore.activeSoundRoutingSettings.midiDestinationUniqueID == 42)
    }

    private func makePassage() -> PracticePassage? {
        let source = PracticeSourceMeasureID(partID: "P1", sourceMeasureIndex: 0, sourceNumberToken: "1")
        return PracticePassage(
            start: PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0),
            end: PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)
        )
    }
}

private struct FixedPracticeSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode = .step
    let practiceHandMode: PracticeHandMode = .both
    let audioRecognitionDetectorMode: PracticeAudioRecognitionDetectorMode = .harmonicTemplate
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private final class CapturingRoundDefaultsStore: PracticeRoundDefaultsStoreProtocol, @unchecked Sendable {
    var tempoScale: Double = 1
    var loopEnabled = false
    var requiredSuccesses = 3
    var savedHandMode: PracticeHandMode?

    func save(
        handMode: PracticeHandMode,
        manualAdvanceMode _: ManualAdvanceMode,
        soundRoutingSettings _: PracticeSoundRoutingSettings,
        tempoScale: Double,
        loopEnabled: Bool,
        requiredSuccesses: Int
    ) {
        savedHandMode = handMode
        self.tempoScale = tempoScale
        self.loopEnabled = loopEnabled
        self.requiredSuccesses = requiredSuccesses
    }
}
