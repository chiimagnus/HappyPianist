import Foundation

enum PracticeSessionSettingsKeys {
    static let manualAdvanceMode = "practiceManualAdvanceMode"
    static let handMode = "practiceHandMode"
    static let audioRecognitionDetectorMode = "practiceStep3AudioRecognitionMode"
    static let improvBackendKind = "practiceImprovBackendKind"

    static let soundOutputRoute = "practiceSoundOutputRoute"
    static let midiDestinationUniqueID = "practiceMIDIDestinationUniqueID"
    static let sendLocalControlOff = "practiceSendLocalControlOff"
}

protocol PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode { get }
    var practiceHandMode: PracticeHandMode { get }
    var audioRecognitionDetectorMode: PracticeAudioRecognitionDetectorMode { get }
    var soundRoutingSettings: PracticeSoundRoutingSettings { get }
}

struct UserDefaultsPracticeSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var manualAdvanceMode: ManualAdvanceMode {
        ManualAdvanceMode.storageValue(
            from: userDefaults.string(forKey: PracticeSessionSettingsKeys.manualAdvanceMode)
        )
    }

    var practiceHandMode: PracticeHandMode {
        PracticeHandMode.storageValue(from: userDefaults.string(forKey: PracticeSessionSettingsKeys.handMode))
    }

    var audioRecognitionDetectorMode: PracticeAudioRecognitionDetectorMode {
        guard let rawValue = userDefaults.string(forKey: PracticeSessionSettingsKeys.audioRecognitionDetectorMode),
              let mode = PracticeAudioRecognitionDetectorMode(rawValue: rawValue)
        else {
            return .harmonicTemplate
        }
        return mode
    }

    var soundRoutingSettings: PracticeSoundRoutingSettings {
        let outputRoute: PracticeSoundOutputRoute
        if let rawValue = userDefaults.string(forKey: PracticeSessionSettingsKeys.soundOutputRoute),
           let route = PracticeSoundOutputRoute(rawValue: rawValue)
        {
            outputRoute = route
        } else {
            outputRoute = .localSampler
        }

        let midiDestinationUniqueID: Int32?
        if let number = userDefaults.object(forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID) as? NSNumber {
            let value = number.int32Value
            midiDestinationUniqueID = value != 0 ? value : nil
        } else {
            midiDestinationUniqueID = nil
        }

        return PracticeSoundRoutingSettings(
            outputRoute: outputRoute,
            midiDestinationUniqueID: midiDestinationUniqueID,
            sendLocalControlOff: userDefaults.bool(forKey: PracticeSessionSettingsKeys.sendLocalControlOff)
        )
    }
}
