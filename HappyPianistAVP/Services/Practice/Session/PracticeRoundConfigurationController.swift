import Foundation
import Observation

protocol PracticeRoundDefaultsStoreProtocol {
    var tempoScale: Double { get }
    var loopEnabled: Bool { get }
    var requiredSuccesses: Int { get }

    func save(
        handMode: PracticeHandMode,
        manualAdvanceMode: ManualAdvanceMode,
        soundRoutingSettings: PracticeSoundRoutingSettings,
        tempoScale: Double,
        loopEnabled: Bool,
        requiredSuccesses: Int
    )
}

struct UserDefaultsPracticeRoundDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var tempoScale: Double {
        let stored = userDefaults.object(forKey: PracticeSessionSettingsKeys.tempoScale) as? Double ?? 0.6
        return min(max(stored, PracticeRoundConfiguration.supportedTempoRange.lowerBound), PracticeRoundConfiguration.supportedTempoRange.upperBound)
    }

    var loopEnabled: Bool {
        guard userDefaults.object(forKey: PracticeSessionSettingsKeys.loopEnabled) != nil else { return true }
        return userDefaults.bool(forKey: PracticeSessionSettingsKeys.loopEnabled)
    }

    var requiredSuccesses: Int {
        let stored = userDefaults.object(forKey: PracticeSessionSettingsKeys.requiredSuccesses) as? Int ?? 3
        return min(max(stored, PracticeRoundConfiguration.supportedSuccessRange.lowerBound), PracticeRoundConfiguration.supportedSuccessRange.upperBound)
    }

    func save(
        handMode: PracticeHandMode,
        manualAdvanceMode: ManualAdvanceMode,
        soundRoutingSettings: PracticeSoundRoutingSettings,
        tempoScale: Double,
        loopEnabled: Bool,
        requiredSuccesses: Int
    ) {
        userDefaults.set(handMode.rawValue, forKey: PracticeSessionSettingsKeys.handMode)
        userDefaults.set(manualAdvanceMode.rawValue, forKey: PracticeSessionSettingsKeys.manualAdvanceMode)
        userDefaults.set(soundRoutingSettings.outputRoute.rawValue, forKey: PracticeSessionSettingsKeys.soundOutputRoute)
        userDefaults.set(Int(soundRoutingSettings.midiDestinationUniqueID ?? 0), forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID)
        userDefaults.set(soundRoutingSettings.sendLocalControlOff, forKey: PracticeSessionSettingsKeys.sendLocalControlOff)
        userDefaults.set(tempoScale, forKey: PracticeSessionSettingsKeys.tempoScale)
        userDefaults.set(loopEnabled, forKey: PracticeSessionSettingsKeys.loopEnabled)
        userDefaults.set(requiredSuccesses, forKey: PracticeSessionSettingsKeys.requiredSuccesses)
    }
}

@MainActor
@Observable
final class PracticeRoundConfigurationController {
    private let stateStore: PracticeSessionStateStore
    private let defaultsStore: any PracticeRoundDefaultsStoreProtocol
    private let freshRequiredSuccesses: Int

    var pendingPassage: PracticePassage?
    var pendingHandMode: PracticeHandMode
    var pendingManualAdvanceMode: ManualAdvanceMode
    var pendingSoundOutputRoute: PracticeSoundOutputRoute
    var pendingMIDIDestinationUniqueID: Int
    var pendingSendLocalControlOff: Bool
    var pendingTempoScale: Double
    var pendingLoopEnabled: Bool
    var pendingRequiredSuccesses: Int

    init(
        stateStore: PracticeSessionStateStore,
        settingsProvider: any PracticeSessionSettingsProviderProtocol,
        defaultsStore: any PracticeRoundDefaultsStoreProtocol = UserDefaultsPracticeRoundDefaultsStore()
    ) {
        self.stateStore = stateStore
        self.defaultsStore = defaultsStore
        freshRequiredSuccesses = defaultsStore.requiredSuccesses
        pendingPassage = nil
        pendingHandMode = settingsProvider.practiceHandMode
        pendingManualAdvanceMode = settingsProvider.manualAdvanceMode
        pendingSoundOutputRoute = settingsProvider.soundRoutingSettings.outputRoute
        pendingMIDIDestinationUniqueID = Int(settingsProvider.soundRoutingSettings.midiDestinationUniqueID ?? 0)
        pendingSendLocalControlOff = settingsProvider.soundRoutingSettings.sendLocalControlOff
        pendingTempoScale = defaultsStore.tempoScale
        pendingLoopEnabled = defaultsStore.loopEnabled
        pendingRequiredSuccesses = freshRequiredSuccesses

        stateStore.activeManualAdvanceMode = pendingManualAdvanceMode
        stateStore.activeSoundRoutingSettings = pendingSoundRoutingSettings
    }

    var pendingSoundRoutingSettings: PracticeSoundRoutingSettings {
        PracticeSoundRoutingSettings(
            outputRoute: pendingSoundOutputRoute,
            midiDestinationUniqueID: Int32(exactly: pendingMIDIDestinationUniqueID).flatMap { $0 == 0 ? nil : $0 },
            sendLocalControlOff: pendingSendLocalControlOff
        )
    }

    var pendingConfiguration: PracticeRoundConfiguration? {
        guard let pendingPassage else { return nil }
        return PracticeRoundConfiguration(
            passage: pendingPassage,
            handMode: pendingHandMode,
            tempoScale: pendingTempoScale,
            loopEnabled: pendingLoopEnabled,
            requiredSuccesses: pendingRequiredSuccesses
        )
    }

    var hasPendingChanges: Bool {
        pendingConfiguration != stateStore.activeRoundConfiguration ||
            pendingManualAdvanceMode != stateStore.activeManualAdvanceMode ||
            pendingSoundRoutingSettings != stateStore.activeSoundRoutingSettings
    }

    func installFreshFullScoreConfiguration(passage: PracticePassage) {
        let configuration = PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: freshRequiredSuccesses
        )
        installWithoutSavingDefaults(configuration)
    }

    func installHistoricalPreferences(
        _ preferences: PracticeHistoricalPreferences,
        passage: PracticePassage
    ) {
        installWithoutSavingDefaults(PracticeRoundConfiguration(
            passage: passage,
            handMode: preferences.handMode,
            tempoScale: preferences.tempoScale,
            loopEnabled: preferences.loopEnabled,
            requiredSuccesses: preferences.requiredSuccesses
        ))
    }

    private func installWithoutSavingDefaults(_ configuration: PracticeRoundConfiguration) {
        pendingPassage = configuration.passage
        pendingHandMode = configuration.handMode
        pendingTempoScale = configuration.tempoScale
        pendingLoopEnabled = configuration.loopEnabled
        pendingRequiredSuccesses = configuration.requiredSuccesses
        stateStore.activeRoundConfiguration = configuration
        stateStore.roundGeneration += 1
    }

    func resetSong() {
        pendingPassage = nil
        stateStore.activeRoundConfiguration = nil
    }

    @discardableResult
    func applyPending() -> Bool {
        guard let pendingConfiguration else { return false }
        let routingChanged = pendingSoundRoutingSettings != stateStore.activeSoundRoutingSettings

        stateStore.activeRoundConfiguration = pendingConfiguration
        stateStore.activeManualAdvanceMode = pendingManualAdvanceMode
        stateStore.activeSoundRoutingSettings = pendingSoundRoutingSettings
        stateStore.roundGeneration += 1

        defaultsStore.save(
            handMode: pendingHandMode,
            manualAdvanceMode: pendingManualAdvanceMode,
            soundRoutingSettings: pendingSoundRoutingSettings,
            tempoScale: pendingConfiguration.tempoScale,
            loopEnabled: pendingConfiguration.loopEnabled,
            requiredSuccesses: pendingConfiguration.requiredSuccesses
        )
        return routingChanged
    }

    func restoreActiveConfiguration(_ configuration: PracticeRoundConfiguration) {
        installWithoutSavingDefaults(configuration)
    }

    func beginNextRound() {
        guard stateStore.activeRoundConfiguration != nil else { return }
        stateStore.roundGeneration += 1
    }
}
