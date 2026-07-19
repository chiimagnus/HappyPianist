import Foundation
import Observation

@MainActor
@Observable
final class ARGuideRecordingViewModel {
    let takeLibraryViewModel: TakeLibraryViewModel
    let takePlaybackViewModel: TakePlaybackViewModel

    var isRecording = false
    var recordingStartDate: Date?

    private let onMIDI1Event: @MainActor (MIDI1InputEvent) -> Void
    private let onMIDI2Event: @MainActor (MIDI2InputEvent) -> Void

    @ObservationIgnored
    private lazy var midiRecordingState: MIDIRecordingState = .init(
        onStateChanged: { [weak self] state in
            guard let self else { return }
            isRecording = state.isRecording
            recordingStartDate = state.recordingStartDate
        },
        onTakeRecorded: { [weak self] take in
            self?.takeLibraryViewModel.addTake(take)
        },
        onMIDI1Event: { [weak self] event in
            self?.onMIDI1Event(event)
        },
        onMIDI2Event: { [weak self] event in
            self?.onMIDI2Event(event)
        }
    )
    @ObservationIgnored private var playbackStopTask: Task<Void, Never>?

    init(
        takeLibraryViewModel: TakeLibraryViewModel? = nil,
        takePlaybackViewModel: TakePlaybackViewModel? = nil,
        onMIDI1Event: @escaping @MainActor (MIDI1InputEvent) -> Void = { _ in },
        onMIDI2Event: @escaping @MainActor (MIDI2InputEvent) -> Void = { _ in },
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.takeLibraryViewModel = takeLibraryViewModel ?? TakeLibraryViewModel()
        if let takePlaybackViewModel {
            self.takePlaybackViewModel = takePlaybackViewModel
        } else {
            let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
            let playbackService: PracticeSequencerPlaybackServiceProtocol =
                isRunningUnitTests
                    ? NoopPracticeSequencerPlaybackService()
                    : AVAudioSequencerPracticePlaybackService(
                        soundFontResourceName: "SalC5Light2",
                        diagnosticsReporter: diagnosticsReporter
                    )
            self.takePlaybackViewModel = TakePlaybackViewModel(
                controller: TakePlaybackController(playbackService: playbackService)
            )
        }
        self.onMIDI1Event = onMIDI1Event
        self.onMIDI2Event = onMIDI2Event
    }

    var takes: [RecordingTake] {
        takeLibraryViewModel.takes
    }

    var errorMessage: String? {
        takeLibraryViewModel.errorMessage
    }

    var recordingElapsedText: String {
        guard let startDate = recordingStartDate else { return "00:00" }
        let elapsed = Date.now.timeIntervalSince(startDate)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let minutesText = minutes.formatted(.number.precision(.integerLength(2)))
        let secondsText = seconds.formatted(.number.precision(.integerLength(2)))
        return "\(minutesText):\(secondsText)"
    }

    func refreshMIDISubscriptionIfNeeded(
        usesBluetoothMIDIInput: Bool,
        eventSource: (any PracticeInputEventSourceProtocol)?
    ) {
        midiRecordingState.refreshMIDISubscriptionIfNeeded(
            usesBluetoothMIDIInput: usesBluetoothMIDIInput,
            eventSource: eventSource
        )
    }

    func recordTakeFromKeyContactIfNeeded(
        usesBluetoothMIDIInput: Bool,
        isVirtualPianoEnabled: Bool,
        keyContact: KeyContactResult,
        nowUptimeSeconds: TimeInterval
    ) {
        midiRecordingState.recordTakeFromKeyContactIfNeeded(
            usesBluetoothMIDIInput: usesBluetoothMIDIInput,
            isVirtualPianoEnabled: isVirtualPianoEnabled,
            keyContact: keyContact,
            nowUptimeSeconds: nowUptimeSeconds
        )
    }

    func startRecording(canRecord: Bool) async {
        guard canRecord else { return }
        await playbackStopTask?.value
        await takePlaybackViewModel.stop()
        midiRecordingState.startRecordingIfPossible(canRecord: canRecord)
    }

    func stopRecording() {
        midiRecordingState.stopRecordingIfNeeded()
    }

    func dismissError() {
        takeLibraryViewModel.dismissError()
    }

    func renameTake(id: UUID, name: String) {
        takeLibraryViewModel.rename(takeID: id, to: name)
    }

    func deleteTake(id: UUID) async {
        await playbackStopTask?.value
        if takePlaybackViewModel.currentTakeID == id {
            await takePlaybackViewModel.stop()
        }
        takeLibraryViewModel.delete(takeID: id)
    }

    func clearAllTakes() async {
        await playbackStopTask?.value
        await takePlaybackViewModel.stop()
        takeLibraryViewModel.clearAll()
    }

    func makeMIDIExport(for take: RecordingTake) throws -> RecordingMIDIExport {
        try takeLibraryViewModel.makeMIDIExport(for: take)
    }

    func stop() {
        midiRecordingState.stop()
        let previousStopTask = playbackStopTask
        let takePlaybackViewModel = takePlaybackViewModel
        playbackStopTask = Task {
            await previousStopTask?.value
            await takePlaybackViewModel.stop()
        }
    }
}
