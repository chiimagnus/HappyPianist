import Foundation
import Observation
import os

@MainActor
@Observable
final class ARGuideRecordingViewModel {
    let takeLibraryViewModel: TakeLibraryViewModel
    let takePlaybackViewModel: TakePlaybackViewModel

    var isRecording = false
    var recordingStartDate: Date?

    private let logger: Logger
    private let onMIDI1Event: @MainActor (MIDI1InputEvent) -> Void
    private let onMIDI2Event: @MainActor (MIDI2InputEvent) -> Void

    @ObservationIgnored
    private lazy var midiRecordingState: MIDIRecordingState = MIDIRecordingState(
        logger: logger,
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

    init(
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
            category: "PracticeInput-Recording"
        ),
        takeLibraryViewModel: TakeLibraryViewModel? = nil,
        takePlaybackViewModel: TakePlaybackViewModel? = nil,
        onMIDI1Event: @escaping @MainActor (MIDI1InputEvent) -> Void = { _ in },
        onMIDI2Event: @escaping @MainActor (MIDI2InputEvent) -> Void = { _ in }
    ) {
        self.logger = logger
        self.takeLibraryViewModel = takeLibraryViewModel ?? TakeLibraryViewModel()
        self.takePlaybackViewModel = takePlaybackViewModel ?? TakePlaybackViewModel(
            controller: TakePlaybackController(
                playbackService: AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
            )
        )
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

    func startRecording(canRecord: Bool) {
        guard canRecord else { return }
        takePlaybackViewModel.stop()
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

    func deleteTake(id: UUID) {
        if takePlaybackViewModel.currentTakeID == id {
            takePlaybackViewModel.stop()
        }
        takeLibraryViewModel.delete(takeID: id)
    }

    func clearAllTakes() {
        takePlaybackViewModel.stop()
        takeLibraryViewModel.clearAll()
    }

    func makeMIDIExport(for take: RecordingTake) throws -> RecordingMIDIExport {
        try takeLibraryViewModel.makeMIDIExport(for: take)
    }

    func stop() {
        midiRecordingState.stop()
        takePlaybackViewModel.stop()
    }
}
