import Foundation
import Testing
@testable import LonelyPianist

@MainActor
@Test
func setSingleKeyMappingWritesKeyStrokeAndClampsNote() {
    var payload = MappingConfigPayload.empty
    payload.defaultVelocityThreshold = 88

    let context = makeContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 188, keyCode: 40)

    guard let activeConfig = context.viewModel.activeConfig,
          let rule = activeConfig.payload.singleKeyRules.first(where: { $0.note == 127 }) else {
        Issue.record("Expected a single-key rule at note 127")
        return
    }

    #expect(rule.output == KeyStroke(keyCode: 40))
    #expect(rule.velocityThreshold == 88)
}

@MainActor
@Test
func setSingleKeyMappingKeepsOnlyOneRulePerNote() {
    let duplicatedRules: [SingleKeyMappingRule] = [
        SingleKeyMappingRule(
            note: 60,
            output: KeyStroke(keyCode: 7),
            velocityThreshold: 70
        ),
        SingleKeyMappingRule(
            note: 60,
            output: KeyStroke(keyCode: 8),
            velocityThreshold: 111
        )
    ]

    let payload = MappingConfigPayload(
        velocityEnabled: true,
        defaultVelocityThreshold: 90,
        singleKeyRules: duplicatedRules,
        chordRules: []
    )

    let context = makeContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 60, keyCode: 12)

    guard let activeConfig = context.viewModel.activeConfig else {
        Issue.record("Missing active config")
        return
    }

    let rulesAtNote60 = activeConfig.payload.singleKeyRules.filter { $0.note == 60 }
    #expect(rulesAtNote60.count == 1)
    #expect(rulesAtNote60.first?.output == KeyStroke(keyCode: 12))
    #expect(rulesAtNote60.first?.velocityThreshold == 111)
}

@MainActor
@Test
func chordCrudNormalizesNotesAndPersists() {
    let context = makeContext(payload: .empty)
    let copyStroke = KeyStroke(keyCode: 8, modifiers: [.command])

    context.viewModel.createChordRule(notes: [67, 60, 67, 64], output: copyStroke)

    guard let created = context.viewModel.activeConfig?.payload.chordRules.first else {
        Issue.record("Expected one chord rule after creation")
        return
    }

    #expect(created.notes == [60, 64, 67])
    #expect(created.output == copyStroke)

    var updated = created
    updated.notes = [69, 62, 69]
    updated.output = KeyStroke(keyCode: 35, modifiers: [.command, .shift])
    context.viewModel.updateChordRule(updated)

    guard let updatedRule = context.viewModel.activeConfig?.payload.chordRules.first(where: { $0.id == created.id }) else {
        Issue.record("Expected updated chord rule")
        return
    }

    #expect(updatedRule.notes == [62, 69])
    #expect(updatedRule.output == KeyStroke(keyCode: 35, modifiers: [.command, .shift]))

    context.viewModel.deleteChordRule(id: created.id)
    #expect(context.viewModel.activeConfig?.payload.chordRules.isEmpty == true)
}

@MainActor
@Test
func createChordRuleIgnoresEmptyNotes() {
    let context = makeContext(payload: .empty)

    context.viewModel.createChordRule(notes: [], output: KeyStroke(keyCode: 8, modifiers: [.command]))

    #expect(context.viewModel.activeConfig?.payload.chordRules.isEmpty == true)
}

@MainActor
@Test
func mappingEditsPersistAfterRebootstrap() {
    var payload = MappingConfigPayload.empty
    payload.defaultVelocityThreshold = 92

    let context = makeContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 60, keyCode: 0)
    context.viewModel.createChordRule(notes: [67, 60, 64], output: KeyStroke(keyCode: 8, modifiers: [.command]))

    let reloadedViewModel = makeViewModel(configRepository: context.configRepository)
    reloadedViewModel.bootstrap()

    guard let activeConfig = reloadedViewModel.activeConfig else {
        Issue.record("Expected active config after rebootstrap")
        return
    }

    #expect(activeConfig.payload.singleKeyRules.contains(where: { $0.note == 60 && $0.output == KeyStroke(keyCode: 0) }))
    #expect(activeConfig.payload.chordRules.contains(where: { $0.notes == [60, 64, 67] && $0.output == KeyStroke(keyCode: 8, modifiers: [.command]) }))
}

@MainActor
private func makeContext(payload: MappingConfigPayload) -> (
    viewModel: LonelyPianistViewModel,
    configRepository: MappingConfigRepositoryTestDouble
) {
    let config = MappingConfig(
        id: UUID(),
        updatedAt: Date(timeIntervalSince1970: 1000),
        payload: payload
    )

    let configRepository = MappingConfigRepositoryTestDouble(config: config)
    let viewModel = makeViewModel(configRepository: configRepository)

    viewModel.bootstrap()

    return (viewModel, configRepository)
}

@MainActor
private func makeViewModel(configRepository: MappingConfigRepositoryTestDouble) -> LonelyPianistViewModel {
    let midi = MIDIInputServiceMock()
    let keyboard = KeyboardEventServiceMock()
    let permission = PermissionServiceMock()
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

    return LonelyPianistViewModel(
        midiInputService: midi,
        keyboardEventService: keyboard,
        permissionService: permission,
        repository: configRepository,
        recordingRepository: recordingRepository,
        recordingService: recordingService,
        playbackService: playback,
        mappingEngine: mapping,
        shortcutService: shortcut,
        dialogueManager: dialogueManager
    )
}
