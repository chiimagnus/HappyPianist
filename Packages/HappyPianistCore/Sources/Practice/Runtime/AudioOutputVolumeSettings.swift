import Foundation

public enum AudioOutputVolumeSettings {
    public static let userDefaultsKey = "audioOutputVolume"
    public static let defaultValue: Float = 1.0

    public static func readAudioOutputVolume(from userDefaults: UserDefaults = .standard) -> Float {
        guard let number = userDefaults.object(forKey: userDefaultsKey) as? NSNumber else {
            return defaultValue
        }

        let value = number.floatValue
        guard value.isFinite else { return Self.defaultValue }
        return min(max(value, 0.0), 1.0)
    }
}
