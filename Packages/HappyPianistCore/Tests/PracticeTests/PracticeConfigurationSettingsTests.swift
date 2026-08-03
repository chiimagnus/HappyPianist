import Foundation
import MusicXML
import Practice
import Testing

@MainActor
struct PracticeConfigurationSettingsTests {
    @Test func emptyDefaultsUseApprovedFreshValues() throws {
        let suiteName = "PracticeRoundDefaults-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsPracticeRoundDefaultsStore(userDefaults: userDefaults)

        #expect(store.tempoScale == 0.6)
        #expect(store.loopEnabled)
        #expect(store.requiredSuccesses == 3)

        userDefaults.set(1.0, forKey: PracticeSessionSettingsKeys.tempoScale)
        userDefaults.set(false, forKey: PracticeSessionSettingsKeys.loopEnabled)
        #expect(store.tempoScale == 1.0)
        #expect(store.loopEnabled == false)
    }

    @Test func pendingChangesDoNotMutateActiveRoundUntilApply() throws {
        let stateStore = TestRoundConfigurationStateStore()
        let defaults = CapturingRoundDefaultsStore()
        let controller = PracticeRoundConfigurationController(
            stateStore: stateStore,
            settingsProvider: FixedPracticeSettingsProvider(),
            defaultsStore: defaults
        )
        let passage = try #require(makePassage())
        controller.installFreshFullScoreConfiguration(passage: passage)

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
        let stateStore = TestRoundConfigurationStateStore()
        let controller = PracticeRoundConfigurationController(
            stateStore: stateStore,
            settingsProvider: FixedPracticeSettingsProvider(),
            defaultsStore: CapturingRoundDefaultsStore()
        )
        try controller.installFreshFullScoreConfiguration(passage: #require(makePassage()))

        controller.pendingSoundOutputRoute = .externalMIDIDestination
        controller.pendingMIDIDestinationUniqueID = 42

        #expect(stateStore.activeSoundRoutingSettings.outputRoute == .localSampler)
        #expect(controller.applyPending())
        #expect(stateStore.activeSoundRoutingSettings.outputRoute == .localSampler)
        #expect(controller.pendingSoundRoutingSettings.outputRoute == .externalMIDIDestination)
        #expect(controller.pendingSoundRoutingSettings.midiDestinationUniqueID == 42)
        #expect(controller.applyPending())
    }

    @Test func historicalPreferencesInstallWithoutWritingDefaults() throws {
        let stateStore = TestRoundConfigurationStateStore()
        let defaults = CapturingRoundDefaultsStore()
        let controller = PracticeRoundConfigurationController(
            stateStore: stateStore,
            settingsProvider: FixedPracticeSettingsProvider(),
            defaultsStore: defaults
        )
        let passage = try #require(makePassage())

        controller.installHistoricalPreferences(
            PracticeHistoricalPreferences(
                handMode: .left,
                tempoScale: 0.7,
                loopEnabled: true,
                requiredSuccesses: 4
            ),
            passage: passage
        )

        #expect(controller.pendingConfiguration == stateStore.activeRoundConfiguration)
        #expect(stateStore.activeRoundConfiguration?.passage == passage)
        #expect(stateStore.activeRoundConfiguration?.handMode == .left)
        #expect(defaults.saveCount == 0)
    }

    @Test func defaultsToLocalSamplerAndParsesTheSavedRoute() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let defaults = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(defaults.soundRoutingSettings.outputRoute == .localSampler)
        #expect(defaults.soundRoutingSettings.midiDestinationUniqueID == nil)
        #expect(defaults.soundRoutingSettings.sendLocalControlOff == false)

        userDefaults.set(
            PracticeSoundOutputRoute.externalMIDIDestination.rawValue,
            forKey: PracticeSessionSettingsKeys.soundOutputRoute
        )
        userDefaults.set(-1234, forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID)
        userDefaults.set(true, forKey: PracticeSessionSettingsKeys.sendLocalControlOff)

        let restored = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(restored.soundRoutingSettings.outputRoute == .externalMIDIDestination)
        #expect(restored.soundRoutingSettings.midiDestinationUniqueID == -1234)
        #expect(restored.soundRoutingSettings.sendLocalControlOff)
    }

    @Test func zeroDestinationIsIgnoredAndRoundDefaultsKeepTheExistingKeys() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(0, forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID)
        let provider = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == nil)

        let store = UserDefaultsPracticeRoundDefaultsStore(userDefaults: userDefaults)
        store.save(
            handMode: .left,
            manualAdvanceMode: .measure,
            soundRoutingSettings: PracticeSoundRoutingSettings(
                outputRoute: .externalMIDIDestination,
                midiDestinationUniqueID: 99,
                sendLocalControlOff: true
            ),
            tempoScale: 0.75,
            loopEnabled: true,
            requiredSuccesses: 4
        )

        #expect(provider.practiceHandMode == .left)
        #expect(provider.manualAdvanceMode == .measure)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == 99)
        #expect(store.tempoScale == 0.75)
        #expect(store.loopEnabled)
        #expect(store.requiredSuccesses == 4)
    }

    private func makePassage(partID: String = "P1", sourceIndex: Int = 0) -> PracticePassage? {
        let source = PracticeSourceMeasureID(
            partID: partID,
            sourceMeasureIndex: sourceIndex,
            sourceNumberToken: "\(sourceIndex + 1)"
        )
        return PracticePassage(
            start: PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0),
            end: PracticeMeasureOccurrenceID(sourceMeasureID: source, occurrenceIndex: 0)
        )
    }
}

@MainActor
private final class TestRoundConfigurationStateStore: PracticeRoundConfigurationStateStoring {
    var activeRoundConfiguration: PracticeRoundConfiguration?
    var activeManualAdvanceMode: ManualAdvanceMode = .step
    var activeSoundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
    var roundGeneration = 0
}

private struct FixedPracticeSettingsProvider: PracticeSessionSettingsProviderProtocol {
    let manualAdvanceMode: ManualAdvanceMode = .step
    let practiceHandMode: PracticeHandMode = .both
    let soundRoutingSettings = PracticeSoundRoutingSettings(
        outputRoute: .localSampler,
        midiDestinationUniqueID: nil,
        sendLocalControlOff: false
    )
}

private final class CapturingRoundDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    var tempoScale: Double = 1
    var loopEnabled = false
    var requiredSuccesses = 3
    var savedHandMode: PracticeHandMode?
    private(set) var saveCount = 0

    func save(
        handMode: PracticeHandMode,
        manualAdvanceMode _: ManualAdvanceMode,
        soundRoutingSettings _: PracticeSoundRoutingSettings,
        tempoScale: Double,
        loopEnabled: Bool,
        requiredSuccesses: Int
    ) {
        saveCount += 1
        savedHandMode = handMode
        self.tempoScale = tempoScale
        self.loopEnabled = loopEnabled
        self.requiredSuccesses = requiredSuccesses
    }
}
