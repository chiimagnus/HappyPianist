import Foundation
import MIDI
import Observation

struct MIDIEndpointSettings: Equatable {
    var inputEndpointUniqueID: Int32?
    var outputEndpointUniqueID: Int32?
}

protocol MIDIEndpointSettingsStoring: AnyObject {
    func load() -> MIDIEndpointSettings
    func save(_ settings: MIDIEndpointSettings)
}

final class UserDefaultsMIDIEndpointSettingsStore: MIDIEndpointSettingsStoring {
    private enum Key {
        static let inputEndpointUniqueID = "macMIDI.inputEndpointUniqueID"
        static let outputEndpointUniqueID = "macMIDI.outputEndpointUniqueID"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> MIDIEndpointSettings {
        MIDIEndpointSettings(
            inputEndpointUniqueID: endpointUniqueID(forKey: Key.inputEndpointUniqueID),
            outputEndpointUniqueID: endpointUniqueID(forKey: Key.outputEndpointUniqueID)
        )
    }

    func save(_ settings: MIDIEndpointSettings) {
        save(settings.inputEndpointUniqueID, forKey: Key.inputEndpointUniqueID)
        save(settings.outputEndpointUniqueID, forKey: Key.outputEndpointUniqueID)
    }

    private func endpointUniqueID(forKey key: String) -> Int32? {
        guard let value = userDefaults.object(forKey: key) as? NSNumber else { return nil }
        return Int32(exactly: value.int64Value)
    }

    private func save(_ endpointUniqueID: Int32?, forKey key: String) {
        if let endpointUniqueID {
            userDefaults.set(Int(endpointUniqueID), forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}

protocol MacSelectedMIDIInputControlling: MIDIInputEventSource {
    var onSourceAvailabilityChange: (@Sendable (MIDIInputSourceAvailability) -> Void)? { get set }

    func start() throws
    func stop()
}

extension CoreMIDIInputEventSourceService: MacSelectedMIDIInputControlling {}

enum MIDIInputSelectionState: Equatable {
    case notSelected
    case connected
    case unavailable(Int32)
}

enum MIDIOutputSelectionState: Equatable {
    case notSelected
    case available
    case unavailable(Int32)
}

@MainActor
@Observable
final class MIDISettingsViewModel {
    private let settingsStore: any MIDIEndpointSettingsStoring
    private let inputEndpointDiscovery: () -> [MIDIInputEndpoint]
    private let outputEndpointDiscovery: () -> [MIDIDestinationInfo]
    private let makeInputService: (Int32) -> any MacSelectedMIDIInputControlling
    private let outputService: any MIDIOutputSendingProtocol

    private var activeInputService: (any MacSelectedMIDIInputControlling)?
    private var activeInputGeneration: UInt64?
    private var hasLoaded = false

    private(set) var inputEndpoints: [MIDIInputEndpoint] = []
    private(set) var outputEndpoints: [MIDIDestinationInfo] = []
    private(set) var selectedInputEndpointID: Int32?
    private(set) var selectedOutputEndpointID: Int32?
    private(set) var inputSelectionState: MIDIInputSelectionState = .notSelected
    private(set) var outputSelectionState: MIDIOutputSelectionState = .notSelected
    private(set) var sessionGeneration: UInt64 = 0
    private(set) var errorMessage: String?
    var onSelectedInputLoss: (@MainActor () -> Void)?

    init(
        settingsStore: any MIDIEndpointSettingsStoring,
        inputEndpointDiscovery: @escaping () -> [MIDIInputEndpoint],
        outputEndpointDiscovery: @escaping () -> [MIDIDestinationInfo],
        makeInputService: @escaping (Int32) -> any MacSelectedMIDIInputControlling,
        outputService: any MIDIOutputSendingProtocol
    ) {
        self.settingsStore = settingsStore
        self.inputEndpointDiscovery = inputEndpointDiscovery
        self.outputEndpointDiscovery = outputEndpointDiscovery
        self.makeInputService = makeInputService
        self.outputService = outputService
    }

    func load() {
        guard hasLoaded == false else {
            refreshEndpoints()
            return
        }
        hasLoaded = true
        let settings = settingsStore.load()
        selectedInputEndpointID = settings.inputEndpointUniqueID
        selectedOutputEndpointID = settings.outputEndpointUniqueID
        refreshEndpoints()

        guard let selectedInputEndpointID else {
            inputSelectionState = .notSelected
            return
        }
        guard inputEndpoints.contains(where: { $0.id == selectedInputEndpointID }) else {
            inputSelectionState = .unavailable(selectedInputEndpointID)
            return
        }
        activateSelectedInput(endpointUniqueID: selectedInputEndpointID)
    }

    func refreshEndpoints() {
        inputEndpoints = inputEndpointDiscovery()
        outputEndpoints = outputEndpointDiscovery()
        updateOutputSelectionState()

        if let selectedInputEndpointID,
           inputEndpoints.contains(where: { $0.id == selectedInputEndpointID }) == false
        {
            let hadActiveInput = activeInputService != nil
            retireActiveInput()
            inputSelectionState = .unavailable(selectedInputEndpointID)
            if hadActiveInput {
                errorMessage = "所选 MIDI 输入已断开。请重新连接或重新选择设备。"
                onSelectedInputLoss?()
            }
        }
    }

    func selectInput(endpointUniqueID: Int32?) {
        errorMessage = nil
        retireActiveInput()
        selectedInputEndpointID = endpointUniqueID
        persistSettings()

        guard let endpointUniqueID else {
            inputSelectionState = .notSelected
            return
        }
        guard inputEndpoints.contains(where: { $0.id == endpointUniqueID }) else {
            inputSelectionState = .unavailable(endpointUniqueID)
            errorMessage = "所选 MIDI 输入当前不可用。请重新连接或重新选择设备。"
            return
        }
        activateSelectedInput(endpointUniqueID: endpointUniqueID)
    }

    func selectOutput(endpointUniqueID: Int32?) {
        errorMessage = nil
        if let selectedOutputEndpointID, selectedOutputEndpointID != endpointUniqueID {
            retireOutput(endpointUniqueID: selectedOutputEndpointID)
        }
        selectedOutputEndpointID = endpointUniqueID
        persistSettings()
        updateOutputSelectionState()
    }

    func dismissError() {
        errorMessage = nil
    }

    var selectedAvailableOutputEndpointID: Int32? {
        guard outputSelectionState == .available else { return nil }
        return selectedOutputEndpointID
    }

    func selectedInputForPractice() -> (any MIDIInputEventSource)? {
        guard inputSelectionState == .connected else { return nil }
        return activeInputService
    }

    func resumeSelectedInputMonitoring() {
        refreshEndpoints()
        guard let selectedInputEndpointID else {
            inputSelectionState = .notSelected
            return
        }
        guard inputEndpoints.contains(where: { $0.id == selectedInputEndpointID }) else {
            inputSelectionState = .unavailable(selectedInputEndpointID)
            return
        }
        retireActiveInput()
        activateSelectedInput(endpointUniqueID: selectedInputEndpointID)
    }

    func resetSelectedOutput() {
        guard let selectedOutputEndpointID,
              outputSelectionState == .available
        else {
            return
        }
        retireOutput(endpointUniqueID: selectedOutputEndpointID)
    }

    func handleInputAvailabilityChange(
        _ availability: MIDIInputSourceAvailability,
        generation: UInt64
    ) {
        guard generation == activeInputGeneration else { return }
        switch availability {
        case .connected:
            inputSelectionState = .connected
        case let .selectedEndpointUnavailable(endpointUniqueID):
            guard endpointUniqueID == selectedInputEndpointID else { return }
            sessionGeneration &+= 1
            activeInputService?.onSourceAvailabilityChange = nil
            activeInputService?.stop()
            activeInputService = nil
            activeInputGeneration = nil
            inputSelectionState = .unavailable(endpointUniqueID)
            errorMessage = "所选 MIDI 输入已断开。请重新连接或重新选择设备。"
            onSelectedInputLoss?()
        }
    }

    private func activateSelectedInput(endpointUniqueID: Int32) {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let inputService = makeInputService(endpointUniqueID)
        inputService.onSourceAvailabilityChange = { [weak self] availability in
            Task { @MainActor [weak self] in
                self?.handleInputAvailabilityChange(availability, generation: generation)
            }
        }
        activeInputService = inputService
        activeInputGeneration = generation
        inputSelectionState = .connected

        do {
            try inputService.start()
        } catch {
            inputService.onSourceAvailabilityChange = nil
            inputService.stop()
            activeInputService = nil
            activeInputGeneration = nil
            inputSelectionState = .unavailable(endpointUniqueID)
            errorMessage = "无法启动所选 MIDI 输入。请重新连接或重新选择设备。"
        }
    }

    private func retireActiveInput() {
        sessionGeneration &+= 1
        activeInputService?.onSourceAvailabilityChange = nil
        activeInputService?.stop()
        activeInputService = nil
        activeInputGeneration = nil
    }

    private func retireOutput(endpointUniqueID: Int32) {
        var resetFailed = false
        do {
            try outputService.flushScheduledMessages(destinationUniqueID: endpointUniqueID)
        } catch {
            resetFailed = true
        }
        for channel in UInt8(0) ..< 16 {
            do {
                try outputService.sendAllNotesOff(channel: channel, destinationUniqueID: endpointUniqueID)
            } catch {
                resetFailed = true
            }
            do {
                try outputService.sendAllSoundOff(channel: channel, destinationUniqueID: endpointUniqueID)
            } catch {
                resetFailed = true
            }
        }
        outputService.stop()
        if resetFailed {
            errorMessage = "未能完整停止原 MIDI 输出；请检查设备后再开始播放。"
        }
    }

    private func updateOutputSelectionState() {
        guard let selectedOutputEndpointID else {
            outputSelectionState = .notSelected
            return
        }
        outputSelectionState = outputEndpoints.contains(where: { $0.id == selectedOutputEndpointID })
            ? .available
            : .unavailable(selectedOutputEndpointID)
    }

    private func persistSettings() {
        settingsStore.save(MIDIEndpointSettings(
            inputEndpointUniqueID: selectedInputEndpointID,
            outputEndpointUniqueID: selectedOutputEndpointID
        ))
    }
}
