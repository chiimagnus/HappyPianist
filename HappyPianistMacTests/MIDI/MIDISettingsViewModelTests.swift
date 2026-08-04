import Foundation
import MIDI
import Synchronization
@testable import HappyPianistMac
import Testing

@MainActor
struct MIDISettingsViewModelTests {
    @Test func restoresOnlyEndpointIDsAndStartsOnlyTheSelectedInput() {
        let fixture = MIDISettingsFixture(
            settings: MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: 9),
            inputEndpoints: [
                MIDIInputEndpoint(id: 7, name: "Studio Keyboard"),
                MIDIInputEndpoint(id: 8, name: "Other Keyboard"),
            ],
            outputEndpoints: [MIDIDestinationInfo(id: 9, name: "Studio Synth")]
        )

        fixture.viewModel.load()

        #expect(fixture.viewModel.selectedInputEndpointID == 7)
        #expect(fixture.viewModel.selectedOutputEndpointID == 9)
        #expect(fixture.viewModel.inputSelectionState == .connected)
        #expect(fixture.viewModel.outputSelectionState == .available)
        #expect(fixture.createdInputEndpointIDs == [7])
        #expect(fixture.input(for: 7)?.startCount == 1)
        #expect(fixture.output.calls.isEmpty)
    }

    @Test func missingStoredInputNeedsExplicitReselectionWithoutFallback() {
        let fixture = MIDISettingsFixture(
            settings: MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: nil),
            inputEndpoints: [MIDIInputEndpoint(id: 8, name: "Available Keyboard")]
        )

        fixture.viewModel.load()

        #expect(fixture.viewModel.inputSelectionState == .unavailable(7))
        #expect(fixture.viewModel.selectedInputEndpointID == 7)
        #expect(fixture.createdInputEndpointIDs.isEmpty)

        fixture.viewModel.selectInput(endpointUniqueID: 8)

        #expect(fixture.viewModel.inputSelectionState == .connected)
        #expect(fixture.createdInputEndpointIDs == [8])
        #expect(fixture.settingsStore.lastSavedSettings?.inputEndpointUniqueID == 8)
    }

    @Test func selectedInputLossStopsAndInvalidatesWithoutSelectingAnotherSource() async {
        let fixture = MIDISettingsFixture(
            settings: MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: nil),
            inputEndpoints: [
                MIDIInputEndpoint(id: 7, name: "Selected Keyboard"),
                MIDIInputEndpoint(id: 8, name: "Other Keyboard"),
            ]
        )
        fixture.viewModel.load()
        let generation = fixture.viewModel.sessionGeneration

        fixture.input(for: 7)?.emit(.selectedEndpointUnavailable(7))
        await Task.yield()

        #expect(fixture.viewModel.inputSelectionState == .unavailable(7))
        #expect(fixture.viewModel.selectedInputEndpointID == 7)
        #expect(fixture.viewModel.sessionGeneration != generation)
        #expect(fixture.input(for: 7)?.stopCount == 1)
        #expect(fixture.createdInputEndpointIDs == [7])

        fixture.viewModel.load()

        #expect(fixture.createdInputEndpointIDs == [7])
    }

    @Test func changingOutputFlushesResetsAndStopsWithoutReplacingInput() {
        let fixture = MIDISettingsFixture(
            settings: MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: 9),
            inputEndpoints: [MIDIInputEndpoint(id: 7, name: "Selected Keyboard")],
            outputEndpoints: [
                MIDIDestinationInfo(id: 9, name: "Old Synth"),
                MIDIDestinationInfo(id: 10, name: "New Synth"),
            ]
        )
        fixture.viewModel.load()

        fixture.viewModel.selectOutput(endpointUniqueID: 10)

        #expect(fixture.viewModel.selectedOutputEndpointID == 10)
        #expect(fixture.settingsStore.lastSavedSettings?.outputEndpointUniqueID == 10)
        #expect(fixture.createdInputEndpointIDs == [7])
        #expect(fixture.output.calls.first == .flush(destinationUniqueID: 9))
        #expect(fixture.output.calls.last == .stop)
        #expect(fixture.output.calls.contains(.allNotesOff(channel: 0, destinationUniqueID: 9)))
        #expect(fixture.output.calls.contains(.allSoundOff(channel: 15, destinationUniqueID: 9)))
    }

    @Test func unavailableOutputLeavesInputAssessmentAvailable() {
        let fixture = MIDISettingsFixture(
            settings: MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: 9),
            inputEndpoints: [MIDIInputEndpoint(id: 7, name: "Selected Keyboard")]
        )

        fixture.viewModel.load()

        #expect(fixture.viewModel.inputSelectionState == .connected)
        #expect(fixture.viewModel.outputSelectionState == .unavailable(9))
        #expect(fixture.input(for: 7)?.startCount == 1)
        #expect(fixture.output.calls.isEmpty)
    }

    @Test func refreshingAfterSelectedInputDisappearsStopsTheOldService() async {
        let fixture = MIDISettingsFixture(
            settings: MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: nil),
            inputEndpoints: [MIDIInputEndpoint(id: 7, name: "Selected Keyboard")]
        )
        fixture.viewModel.load()

        fixture.setInputEndpoints([])
        fixture.viewModel.refreshEndpoints()
        await Task.yield()

        #expect(fixture.viewModel.inputSelectionState == .unavailable(7))
        #expect(fixture.input(for: 7)?.stopCount == 1)
        #expect(fixture.createdInputEndpointIDs == [7])
    }

    @Test func userDefaultsStorePersistsOnlyOptionalEndpointIDs() throws {
        let suiteName = "HappyPianistMacTests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsMIDIEndpointSettingsStore(userDefaults: userDefaults)

        store.save(MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: 9))

        #expect(store.load() == MIDIEndpointSettings(inputEndpointUniqueID: 7, outputEndpointUniqueID: 9))
        let persistedValues = try #require(userDefaults.persistentDomain(forName: suiteName)?.values)
        #expect(persistedValues.allSatisfy { $0 is Int })
    }
}

@MainActor
private final class MIDISettingsFixture {
    let settingsStore: FakeMIDIEndpointSettingsStore
    let output: FakeMIDIOutputService
    let viewModel: MIDISettingsViewModel
    private let inputFactory: FakeMIDIInputFactory
    private let endpointCatalog: FakeMIDIEndpointCatalog

    var createdInputEndpointIDs: [Int32] {
        inputFactory.createdInputEndpointIDs
    }

    init(
        settings: MIDIEndpointSettings,
        inputEndpoints: [MIDIInputEndpoint],
        outputEndpoints: [MIDIDestinationInfo] = []
    ) {
        let inputFactory = FakeMIDIInputFactory()
        let endpointCatalog = FakeMIDIEndpointCatalog(
            inputEndpoints: inputEndpoints,
            outputEndpoints: outputEndpoints
        )
        settingsStore = FakeMIDIEndpointSettingsStore(settings: settings)
        output = FakeMIDIOutputService()
        self.inputFactory = inputFactory
        self.endpointCatalog = endpointCatalog
        viewModel = MIDISettingsViewModel(
            settingsStore: settingsStore,
            inputEndpointDiscovery: { [endpointCatalog] in endpointCatalog.inputEndpoints },
            outputEndpointDiscovery: { [endpointCatalog] in endpointCatalog.outputEndpoints },
            makeInputService: { [inputFactory] endpointUniqueID in
                inputFactory.make(endpointUniqueID: endpointUniqueID)
            },
            outputService: output
        )
    }

    func input(for endpointUniqueID: Int32) -> FakeMIDIInputService? {
        inputFactory.input(for: endpointUniqueID)
    }

    func setInputEndpoints(_ endpoints: [MIDIInputEndpoint]) {
        endpointCatalog.inputEndpoints = endpoints
    }
}

private final class FakeMIDIEndpointCatalog {
    var inputEndpoints: [MIDIInputEndpoint]
    var outputEndpoints: [MIDIDestinationInfo]

    init(inputEndpoints: [MIDIInputEndpoint], outputEndpoints: [MIDIDestinationInfo]) {
        self.inputEndpoints = inputEndpoints
        self.outputEndpoints = outputEndpoints
    }
}

private final class FakeMIDIEndpointSettingsStore: MIDIEndpointSettingsStoring {
    private var settings: MIDIEndpointSettings
    private(set) var lastSavedSettings: MIDIEndpointSettings?

    init(settings: MIDIEndpointSettings) {
        self.settings = settings
    }

    func load() -> MIDIEndpointSettings {
        settings
    }

    func save(_ settings: MIDIEndpointSettings) {
        self.settings = settings
        lastSavedSettings = settings
    }
}

private final class FakeMIDIInputService: MacSelectedMIDIInputControlling {
    var onSourceAvailabilityChange: (@Sendable (MIDIInputSourceAvailability) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func midi1EventsStream() -> AsyncStream<MIDI1InputEvent> {
        AsyncStream { $0.finish() }
    }

    func midi2EventsStream() -> AsyncStream<MIDI2InputEvent> {
        AsyncStream { $0.finish() }
    }

    func start() throws {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func emit(_ availability: MIDIInputSourceAvailability) {
        onSourceAvailabilityChange?(availability)
    }
}

private final class FakeMIDIInputFactory {
    private var inputs: [Int32: FakeMIDIInputService] = [:]
    private(set) var createdInputEndpointIDs: [Int32] = []

    func make(endpointUniqueID: Int32) -> FakeMIDIInputService {
        let input = FakeMIDIInputService()
        createdInputEndpointIDs.append(endpointUniqueID)
        inputs[endpointUniqueID] = input
        return input
    }

    func input(for endpointUniqueID: Int32) -> FakeMIDIInputService? {
        inputs[endpointUniqueID]
    }
}

private final class FakeMIDIOutputService: MIDIOutputSendingProtocol {
    enum Call: Equatable {
        case flush(destinationUniqueID: Int32)
        case allNotesOff(channel: UInt8, destinationUniqueID: Int32)
        case allSoundOff(channel: UInt8, destinationUniqueID: Int32)
        case stop
    }

    private struct State: Sendable {
        var onDestinationRouteWillChange: (@Sendable () -> Void)?
        var onDestinationRouteChange: (@Sendable () -> Task<Void, Never>)?
        var calls: [Call] = []
    }

    private let state = Mutex(State())

    var onDestinationRouteWillChange: (@Sendable () -> Void)? {
        get { state.withLock { $0.onDestinationRouteWillChange } }
        set { state.withLock { $0.onDestinationRouteWillChange = newValue } }
    }

    var onDestinationRouteChange: (@Sendable () -> Task<Void, Never>)? {
        get { state.withLock { $0.onDestinationRouteChange } }
        set { state.withLock { $0.onDestinationRouteChange = newValue } }
    }

    var calls: [Call] {
        state.withLock { $0.calls }
    }

    func start() throws {}
    func stop() { state.withLock { $0.calls.append(.stop) } }
    func listDestinations() -> [MIDIDestinationInfo] { [] }
    func sendMIDI1Messages(_: [TimestampedMIDI1Message], destinationUniqueID _: Int32) throws {}
    func flushScheduledMessages(destinationUniqueID: Int32) throws {
        state.withLock { $0.calls.append(.flush(destinationUniqueID: destinationUniqueID)) }
    }
    func sendNoteOn(note _: UInt8, velocity _: UInt8, channel _: UInt8, destinationUniqueID _: Int32) throws {}
    func sendNoteOff(note _: UInt8, channel _: UInt8, destinationUniqueID _: Int32) throws {}
    func sendControlChange(
        controller _: UInt8,
        value _: UInt8,
        channel _: UInt8,
        destinationUniqueID _: Int32
    ) throws {}
    func sendProgramChange(program _: UInt8, channel _: UInt8, destinationUniqueID _: Int32) throws {}
    func sendAllNotesOff(channel: UInt8, destinationUniqueID: Int32) throws {
        state.withLock {
            $0.calls.append(.allNotesOff(channel: channel, destinationUniqueID: destinationUniqueID))
        }
    }
    func sendAllSoundOff(channel: UInt8, destinationUniqueID: Int32) throws {
        state.withLock {
            $0.calls.append(.allSoundOff(channel: channel, destinationUniqueID: destinationUniqueID))
        }
    }
}
