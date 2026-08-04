import Foundation
import Observation

public enum ManualAdvanceMode: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case step
    case measure

    public var id: String {
        rawValue
    }

    public var title: String {
        self == .step ? "逐步" : "按小节"
    }

    public var nextButtonTitle: String {
        self == .step ? "下一步" : "下一节"
    }

    public var replayButtonTitle: String {
        self == .step ? "播放琴声" : "重播本节"
    }

    public static func storageValue(from rawValue: String?) -> ManualAdvanceMode {
        rawValue.flatMap(ManualAdvanceMode.init(rawValue:)) ?? .step
    }
}

public enum PracticeSoundOutputRoute: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case localSampler
    case externalMIDIDestination

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .localSampler:
            "仅 AVP 发声"
        case .externalMIDIDestination:
            "仅真实钢琴发声"
        }
    }
}

public struct PracticeSoundRoutingSettings: Equatable, Sendable {
    public let outputRoute: PracticeSoundOutputRoute
    public let midiDestinationUniqueID: Int32?
    public let sendLocalControlOff: Bool

    public init(
        outputRoute: PracticeSoundOutputRoute,
        midiDestinationUniqueID: Int32?,
        sendLocalControlOff: Bool
    ) {
        self.outputRoute = outputRoute
        self.midiDestinationUniqueID = midiDestinationUniqueID
        self.sendLocalControlOff = sendLocalControlOff
    }
}

public enum PracticeSessionSettingsKeys {
    public static let manualAdvanceMode = "practiceManualAdvanceMode"
    public static let handMode = "practiceHandMode"
    public static let improvBackendKind = "practiceImprovBackendKind"
    public static let soundOutputRoute = "practiceSoundOutputRoute"
    public static let midiDestinationUniqueID = "practiceMIDIDestinationUniqueID"
    public static let sendLocalControlOff = "practiceSendLocalControlOff"
    public static let tempoScale = "practiceTempoScale"
    public static let loopEnabled = "practiceLoopEnabled"
    public static let requiredSuccesses = "practiceRequiredSuccesses"
}

public protocol PracticeSessionSettingsProviderProtocol {
    var manualAdvanceMode: ManualAdvanceMode { get }
    var practiceHandMode: PracticeHandMode { get }
    var soundRoutingSettings: PracticeSoundRoutingSettings { get }
}

public struct UserDefaultsPracticeSessionSettingsProvider: PracticeSessionSettingsProviderProtocol {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var manualAdvanceMode: ManualAdvanceMode {
        ManualAdvanceMode.storageValue(
            from: userDefaults.string(forKey: PracticeSessionSettingsKeys.manualAdvanceMode)
        )
    }

    public var practiceHandMode: PracticeHandMode {
        PracticeHandMode.storageValue(from: userDefaults.string(forKey: PracticeSessionSettingsKeys.handMode))
    }

    public var soundRoutingSettings: PracticeSoundRoutingSettings {
        let outputRoute: PracticeSoundOutputRoute = if let rawValue = userDefaults.string(
            forKey: PracticeSessionSettingsKeys.soundOutputRoute
        ), let route = PracticeSoundOutputRoute(rawValue: rawValue) {
            route
        } else {
            .localSampler
        }

        let midiDestinationUniqueID: Int32?
        if let number = userDefaults.object(
            forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID
        ) as? NSNumber {
            let value = number.int32Value
            midiDestinationUniqueID = value != 0 ? value : nil
        } else {
            midiDestinationUniqueID = nil
        }

        return PracticeSoundRoutingSettings(
            outputRoute: outputRoute,
            midiDestinationUniqueID: midiDestinationUniqueID,
            sendLocalControlOff: userDefaults.bool(
                forKey: PracticeSessionSettingsKeys.sendLocalControlOff
            )
        )
    }
}

public protocol PracticeRoundDefaultsStoreProtocol {
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

public struct UserDefaultsPracticeRoundDefaultsStore: PracticeRoundDefaultsStoreProtocol {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var tempoScale: Double {
        let stored = userDefaults.object(forKey: PracticeSessionSettingsKeys.tempoScale) as? Double ?? 0.6
        return min(
            max(stored, PracticeRoundConfiguration.supportedTempoRange.lowerBound),
            PracticeRoundConfiguration.supportedTempoRange.upperBound
        )
    }

    public var loopEnabled: Bool {
        guard userDefaults.object(forKey: PracticeSessionSettingsKeys.loopEnabled) != nil else {
            return true
        }
        return userDefaults.bool(forKey: PracticeSessionSettingsKeys.loopEnabled)
    }

    public var requiredSuccesses: Int {
        let stored = userDefaults.object(forKey: PracticeSessionSettingsKeys.requiredSuccesses) as? Int ?? 3
        return min(
            max(stored, PracticeRoundConfiguration.supportedSuccessRange.lowerBound),
            PracticeRoundConfiguration.supportedSuccessRange.upperBound
        )
    }

    public func save(
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
        userDefaults.set(
            Int(soundRoutingSettings.midiDestinationUniqueID ?? 0),
            forKey: PracticeSessionSettingsKeys.midiDestinationUniqueID
        )
        userDefaults.set(
            soundRoutingSettings.sendLocalControlOff,
            forKey: PracticeSessionSettingsKeys.sendLocalControlOff
        )
        userDefaults.set(tempoScale, forKey: PracticeSessionSettingsKeys.tempoScale)
        userDefaults.set(loopEnabled, forKey: PracticeSessionSettingsKeys.loopEnabled)
        userDefaults.set(requiredSuccesses, forKey: PracticeSessionSettingsKeys.requiredSuccesses)
    }
}

@MainActor
public protocol PracticeRoundConfigurationStateStoring: AnyObject {
    var activeRoundConfiguration: PracticeRoundConfiguration? { get set }
    var activeManualAdvanceMode: ManualAdvanceMode { get set }
    var activeSoundRoutingSettings: PracticeSoundRoutingSettings { get set }
    var roundGeneration: Int { get set }
}

@MainActor
@Observable
public final class PracticeRoundConfigurationController {
    private let stateStore: any PracticeRoundConfigurationStateStoring
    private let defaultsStore: any PracticeRoundDefaultsStoreProtocol
    private let freshRequiredSuccesses: Int

    public var pendingPassage: PracticePassage?
    public var pendingHandMode: PracticeHandMode
    public var pendingManualAdvanceMode: ManualAdvanceMode
    public var pendingSoundOutputRoute: PracticeSoundOutputRoute
    public var pendingMIDIDestinationUniqueID: Int
    public var pendingSendLocalControlOff: Bool
    public var pendingTempoScale: Double
    public var pendingLoopEnabled: Bool
    public var pendingRequiredSuccesses: Int

    public init(
        stateStore: any PracticeRoundConfigurationStateStoring,
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

    public var pendingSoundRoutingSettings: PracticeSoundRoutingSettings {
        PracticeSoundRoutingSettings(
            outputRoute: pendingSoundOutputRoute,
            midiDestinationUniqueID: Int32(exactly: pendingMIDIDestinationUniqueID)
                .flatMap { $0 == 0 ? nil : $0 },
            sendLocalControlOff: pendingSendLocalControlOff
        )
    }

    public var pendingConfiguration: PracticeRoundConfiguration? {
        guard let pendingPassage else {
            return nil
        }

        return PracticeRoundConfiguration(
            passage: pendingPassage,
            handMode: pendingHandMode,
            tempoScale: pendingTempoScale,
            loopEnabled: pendingLoopEnabled,
            requiredSuccesses: pendingRequiredSuccesses
        )
    }

    public var hasPendingChanges: Bool {
        pendingConfiguration != stateStore.activeRoundConfiguration ||
            pendingManualAdvanceMode != stateStore.activeManualAdvanceMode ||
            pendingSoundRoutingSettings != stateStore.activeSoundRoutingSettings
    }

    public func installFreshFullScoreConfiguration(passage: PracticePassage) {
        let configuration = PracticeRoundConfiguration(
            passage: passage,
            handMode: .both,
            tempoScale: 1,
            loopEnabled: false,
            requiredSuccesses: freshRequiredSuccesses
        )
        installWithoutSavingDefaults(configuration)
    }

    public func installHistoricalPreferences(
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

    public func resetSong() {
        pendingPassage = nil
        stateStore.activeRoundConfiguration = nil
    }

    @discardableResult
    public func applyPending() -> Bool {
        guard let pendingConfiguration else {
            return false
        }

        let routingChanged = pendingSoundRoutingSettings != stateStore.activeSoundRoutingSettings
        stateStore.activeRoundConfiguration = pendingConfiguration
        stateStore.activeManualAdvanceMode = pendingManualAdvanceMode
        if routingChanged == false {
            stateStore.activeSoundRoutingSettings = pendingSoundRoutingSettings
        }
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

    public func restoreActiveConfiguration(_ configuration: PracticeRoundConfiguration) {
        installWithoutSavingDefaults(configuration)
    }

    public func beginNextRound() {
        guard stateStore.activeRoundConfiguration != nil else {
            return
        }
        stateStore.roundGeneration += 1
    }
}
