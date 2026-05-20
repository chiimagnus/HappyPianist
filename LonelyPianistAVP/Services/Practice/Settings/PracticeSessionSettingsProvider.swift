import Foundation

nonisolated enum PracticeSessionSettingsKeys {
    static let handSeparatedStepMatchingEnabled = "practiceHandSeparatedStepMatchingEnabled"
    static let manualAdvanceMode = "practiceManualAdvanceMode"
    static let audioRecognitionDetectorMode = "practiceStep3AudioRecognitionMode"
}

protocol PracticeSessionSettingsProviderProtocol {
    var isHandSeparatedStepMatchingEnabled: Bool { get }
    var manualAdvanceMode: ManualAdvanceMode { get }
    var audioRecognitionDetectorMode: PracticeAudioRecognitionDetectorMode { get }
}

struct UserDefaultsPracticeSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isHandSeparatedStepMatchingEnabled: Bool {
        userDefaults.bool(forKey: PracticeSessionSettingsKeys.handSeparatedStepMatchingEnabled)
    }

    var manualAdvanceMode: ManualAdvanceMode {
        ManualAdvanceMode.storageValue(
            from: userDefaults.string(forKey: PracticeSessionSettingsKeys.manualAdvanceMode)
        )
    }

    var audioRecognitionDetectorMode: PracticeAudioRecognitionDetectorMode {
        guard let rawValue = userDefaults.string(forKey: PracticeSessionSettingsKeys.audioRecognitionDetectorMode),
              let mode = PracticeAudioRecognitionDetectorMode(rawValue: rawValue)
        else {
            return .harmonicTemplate
        }
        return mode
    }
}
