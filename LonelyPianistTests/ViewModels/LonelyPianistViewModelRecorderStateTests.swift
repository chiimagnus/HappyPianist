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
private func makeContext() -> (
    viewModel: LonelyPianistViewModel,
    repository: RecordingTakeRepositoryMock,
    recordingService: RecordingServiceMock,
    playback: MIDIPlaybackServiceMock,
    keyboard: KeyboardEventServiceMock
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

    let viewModel = LonelyPianistViewModel(
        midiInputService: midi,
        keyboardEventService: keyboard,
        permissionService: permission,
        repository: profileRepository,
        recordingRepository: recordingRepository,
        recordingService: recordingService,
        playbackService: playback,
        mappingEngine: mapping,
        shortcutService: shortcut
    )

    return (viewModel, recordingRepository, recordingService, playback, keyboard)
}
