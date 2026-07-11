import Foundation
@testable import LonelyPianistAVP
import Testing

@MainActor
struct AudioOutputVolumeSettingsTests {
    @Test func defaultIsOneWhenUnset() throws {
        let suiteName = "AudioOutputVolumeSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults) == 1.0)
    }

    @Test func clampsBelowZeroToZero() throws {
        let suiteName = "AudioOutputVolumeSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(-0.1, forKey: AudioOutputVolumeSettings.userDefaultsKey)
        #expect(AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults) == 0.0)
    }

    @Test func clampsAboveOneToOne() throws {
        let suiteName = "AudioOutputVolumeSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(1.1, forKey: AudioOutputVolumeSettings.userDefaultsKey)
        #expect(AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults) == 1.0)
    }

    @Test func nonFiniteFallsBackToDefault() throws {
        let suiteName = "AudioOutputVolumeSettingsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        userDefaults.set(Double.nan, forKey: AudioOutputVolumeSettings.userDefaultsKey)
        #expect(AudioOutputVolumeSettings.readAudioOutputVolume(from: userDefaults) == 1.0)
    }
}
