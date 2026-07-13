import Foundation

enum PracticeSessionSettingsKeys {
    static let manualAdvanceMode = "practiceManualAdvanceMode"
    static let handMode = "practiceHandMode"
    static let improvBackendKind = "practiceImprovBackendKind"

    static let soundOutputRoute = "practiceSoundOutputRoute"
    static let midiDestinationUniqueID = "practiceMIDIDestinationUniqueID"
    static let sendLocalControlOff = "practiceSendLocalControlOff"
    static let tempoScale = "practiceTempoScale"
    static let loopEnabled = "practiceLoopEnabled"
    static let requiredSuccesses = "practiceRequiredSuccesses"
}

protocol PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode { get }
    var practiceHandMode: PracticeHandMode { get }
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

    var soundRoutingSettings: PracticeSoundRoutingSettings {
        let outputRoute: PracticeSoundOutputRoute = if let rawValue = userDefaults.string(forKey: PracticeSessionSettingsKeys.soundOutputRoute),
                                                       let route = PracticeSoundOutputRoute(rawValue: rawValue)
        {
            route
        } else {
            .localSampler
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
