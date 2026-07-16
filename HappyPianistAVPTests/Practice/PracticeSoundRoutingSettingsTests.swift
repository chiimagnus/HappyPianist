import Foundation
@testable import HappyPianistAVP
import Testing

@MainActor
struct PracticeSoundRoutingSettingsTests {
    @Test func defaultsToLocalSampler() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let provider = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(provider.soundRoutingSettings.outputRoute == .localSampler)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == nil)
        #expect(provider.soundRoutingSettings.sendLocalControlOff == false)
    }

    @Test func parsesExternalRouteAndDestinationUniqueID() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(PracticeSoundOutputRoute.externalMIDIDestination.rawValue, forKey: PracticeSessionSettingsKeys.soundOutputRoute)
        userDefaults.set(1234, forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID)
        userDefaults.set(true, forKey: PracticeSessionSettingsKeys.sendLocalControlOff)

        let provider = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(provider.soundRoutingSettings.outputRoute == .externalMIDIDestination)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == 1234)
        #expect(provider.soundRoutingSettings.sendLocalControlOff)
    }

    @Test func parsesNegativeDestinationUniqueID() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(PracticeSoundOutputRoute.externalMIDIDestination.rawValue, forKey: PracticeSessionSettingsKeys.soundOutputRoute)
        userDefaults.set(-1234, forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID)

        let provider = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(provider.soundRoutingSettings.outputRoute == .externalMIDIDestination)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == -1234)
    }

    @Test func ignoresZeroDestinationUniqueID() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(PracticeSoundOutputRoute.externalMIDIDestination.rawValue, forKey: PracticeSessionSettingsKeys.soundOutputRoute)
        userDefaults.set(0, forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID)

        let provider = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == nil)
    }

    @Test func roundDefaultsStoreKeepsExistingPreferenceKeys() throws {
        let suiteName = "PracticeSoundRoutingSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

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

        let provider = UserDefaultsPracticeSessionSettingsProvider(userDefaults: userDefaults)
        #expect(provider.practiceHandMode == .left)
        #expect(provider.manualAdvanceMode == .measure)
        #expect(provider.soundRoutingSettings.midiDestinationUniqueID == 99)
        #expect(store.tempoScale == 0.75)
        #expect(store.loopEnabled)
        #expect(store.requiredSuccesses == 4)
    }
}
