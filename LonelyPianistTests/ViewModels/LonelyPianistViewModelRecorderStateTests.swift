import Foundation
import Testing
@testable import LonelyPianist

@MainActor
@Test
func startRecordingTakeTransitionsToRecording() {
    let context = makeContext()
    context.viewModel.isListening = true

    context.viewModel.startRecordingTake()

    #expect(context.viewModel.recorderMode == .recording)
    #expect(context.recordingService.isRecording)
}

@MainActor
@Test
func stopTransportWhileRecordingSavesTakeAndReturnsToIdle() {
    let context = makeContext()
    context.viewModel.isListening = true

    let note = RecordedNote(
        id: UUID(),
        note: 60,
        velocity: 100,
        channel: 1,
        startOffsetSec: 0.1,
        durationSec: 0.3
    )

    context.recordingService.nextStoppedTake = RecordingTake(
        id: UUID(),
        name: "pending",
        createdAt: Date(),
        updatedAt: Date(),
        durationSec: 0.4,
        notes: [note]
    )

    context.viewModel.startRecordingTake()
    context.viewModel.stopTransport()

    #expect(context.viewModel.recorderMode == .idle)
    #expect(context.repository.savedTakes.count == 1)
    #expect(context.viewModel.takes.count == 1)
}

@MainActor
@Test
func playSelectedTakeDoesNotTriggerKeyboardInjection() {
    let context = makeContext()

    let take = RecordingTake(
        id: UUID(),
        name: "Take",
        createdAt: Date(),
        updatedAt: Date(),
        durationSec: 1.0,
        notes: [
            RecordedNote(id: UUID(), note: 67, velocity: 88, channel: 1, startOffsetSec: 0.0, durationSec: 0.5)
        ]
    )
    context.viewModel.takes = [take]
    context.viewModel.selectedTakeID = take.id

    context.viewModel.playSelectedTake()

    #expect(context.playback.playedTakes.count == 1)
    #expect(context.keyboard.typedTexts.isEmpty)
    #expect(context.keyboard.keyCombos.isEmpty)
}

@MainActor
@Test
func playSelectedTakeFailureUpdatesStatusMessage() {
    let context = makeContext()
    context.playback.playError = DummyError(message: "fail")

    let take = RecordingTake(
        id: UUID(),
        name: "Take",
        createdAt: Date(),
        updatedAt: Date(),
        durationSec: 1.0,
        notes: []
    )
    context.viewModel.takes = [take]
    context.viewModel.selectedTakeID = take.id

    context.viewModel.playSelectedTake()

    #expect(context.viewModel.recorderMode == .idle)
    #expect(context.viewModel.recorderStatusMessage.contains("Playback failed"))
}

@MainActor
@Test
func requestAccessibilityPermissionUpdatesStateWhenGranted() {
    let context = makeContext()
    context.permission.permissionGranted = true

    context.viewModel.requestAccessibilityPermission()

    #expect(context.viewModel.hasAccessibilityPermission == true)
    #expect(context.viewModel.statusMessage == "Accessibility enabled")
}

@MainActor
@Test
func midiEventsUpdatePressedNotesFromServiceCallback() async {
    let context = makeContext()
    context.viewModel.startListening()

    let now = Date(timeIntervalSince1970: 100)
    context.midi.onEvent?(MIDIEvent(type: .noteOn(note: 60, velocity: 100), channel: 1, timestamp: now))
    #expect(await waitForCondition { context.viewModel.pressedNotes == [60] })

    context.midi.onEvent?(MIDIEvent(type: .noteOff(note: 60, velocity: 0), channel: 1, timestamp: now.addingTimeInterval(0.1)))
    #expect(await waitForCondition { context.viewModel.pressedNotes.isEmpty })
}

@MainActor
private func waitForCondition(
    timeoutMilliseconds: UInt64 = 200,
    pollMilliseconds: UInt64 = 5,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let effectivePoll = max(1, pollMilliseconds)
    let iterations = max(1, Int(timeoutMilliseconds / effectivePoll))

    for _ in 0..<iterations {
        if condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: effectivePoll * 1_000_000)
    }

    return condition()
}

@MainActor
private func makeContext() -> (
    viewModel: LonelyPianistViewModel,
    repository: RecordingTakeRepositoryMock,
    recordingService: RecordingServiceMock,
    playback: MIDIPlaybackServiceMock,
    keyboard: KeyboardEventServiceMock,
    midi: MIDIInputServiceMock,
    permission: PermissionServiceMock
) {
    let midi = MIDIInputServiceMock()
    let keyboard = KeyboardEventServiceMock()
    let permission = PermissionServiceMock()
    let profileRepository = MappingProfileRepositoryMock()
    let recordingRepository = RecordingTakeRepositoryMock()
    let recordingService = RecordingServiceMock()
    let playback = MIDIPlaybackServiceMock()
    let mapping = MappingEngineMock()
    let shortcut = ShortcutServiceMock()
    let clock = ClockMock(nowValue: Date(timeIntervalSince1970: 0))
    let silenceDetectionService = DefaultSilenceDetectionService(clock: clock)
    let dialogueService = WebSocketDialogueService(session: URLSession(configuration: .ephemeral))
    let dialogueManager = DialogueManager(
        clock: clock,
        silenceDetectionService: silenceDetectionService,
        dialogueService: dialogueService,
        recordingRepository: recordingRepository,
        playbackService: playback
    )

    let viewModel = LonelyPianistViewModel(
        midiInputService: midi,
        keyboardEventService: keyboard,
        permissionService: permission,
        repository: profileRepository,
        recordingRepository: recordingRepository,
        recordingService: recordingService,
        playbackService: playback,
        mappingEngine: mapping,
        shortcutService: shortcut,
        dialogueManager: dialogueManager
    )

    return (viewModel, recordingRepository, recordingService, playback, keyboard, midi, permission)
}
