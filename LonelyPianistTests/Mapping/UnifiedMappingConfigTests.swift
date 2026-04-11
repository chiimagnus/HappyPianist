import Foundation
import Testing
@testable import LonelyPianist

@MainActor
@Test
func keyStrokeCodableAndDisplayOrderStable() throws {
    let stroke = KeyStroke(keyCode: 40, modifiers: [.shift, .command, .option, .control])
    let data = try JSONEncoder().encode(stroke)
    let decoded = try JSONDecoder().decode(KeyStroke.self, from: data)

    #expect(decoded == stroke)
    #expect(decoded.displayLabel == "\u{2318}\u{2325}\u{2303}\u{21E7}K")
}

@MainActor
@Test
func keyStrokeDisplayFallsBackToNumericKeyCode() {
    let stroke = KeyStroke(keyCode: 999)
    #expect(stroke.displayLabel == "999")
}

@MainActor
@Test
func mappingEngineAppliesVelocityShiftDerivation() {
    let engine = DefaultMappingEngine()
    let payload = MappingConfigPayload(
        velocityEnabled: true,
        defaultVelocityThreshold: 100,
        singleKeyRules: [
            SingleKeyMappingRule(note: 60, output: KeyStroke(keyCode: 40), velocityThreshold: 100)
        ],
        chordRules: []
    )

    let low = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 90), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(low.count == 1)
    #expect(low.first?.keyStroke == KeyStroke(keyCode: 40))

    _ = engine.process(
        event: MIDIEvent(type: .noteOff(note: 60, velocity: 0), channel: 1, timestamp: .now),
        payload: payload
    )

    let high = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 120), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(high.count == 1)
    #expect(high.first?.keyStroke == KeyStroke(keyCode: 40, modifiers: [.shift]))
}

@MainActor
@Test
func mappingEngineUsesNormalOutputWhenVelocityDisabled() {
    let engine = DefaultMappingEngine()
    let payload = MappingConfigPayload(
        velocityEnabled: false,
        defaultVelocityThreshold: 20,
        singleKeyRules: [
            SingleKeyMappingRule(note: 60, output: KeyStroke(keyCode: 40), velocityThreshold: 1)
        ],
        chordRules: []
    )

    let resolved = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 127), channel: 1, timestamp: .now),
        payload: payload
    )

    #expect(resolved.count == 1)
    #expect(resolved.first?.keyStroke == KeyStroke(keyCode: 40))
}

@MainActor
@Test
func mappingEngineChordUsesStrictEquality() {
    let engine = DefaultMappingEngine()
    let payload = MappingConfigPayload(
        velocityEnabled: false,
        defaultVelocityThreshold: 100,
        singleKeyRules: [],
        chordRules: [
            ChordMappingRule(notes: [60, 64, 67], output: KeyStroke(keyCode: 8, modifiers: [.command]))
        ]
    )

    let first = engine.process(
        event: MIDIEvent(type: .noteOn(note: 60, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(first.isEmpty)

    let second = engine.process(
        event: MIDIEvent(type: .noteOn(note: 64, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(second.isEmpty)

    let matched = engine.process(
        event: MIDIEvent(type: .noteOn(note: 67, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(matched.count == 1)

    let extra = engine.process(
        event: MIDIEvent(type: .noteOn(note: 69, velocity: 80), channel: 1, timestamp: .now),
        payload: payload
    )
    #expect(extra.isEmpty)
}

@MainActor
@Test
func mappingConfigPayloadCodableRoundTrip() throws {
    let payload = MappingConfigPayload(
        velocityEnabled: true,
        defaultVelocityThreshold: 77,
        singleKeyRules: [
            SingleKeyMappingRule(note: 60, output: KeyStroke(keyCode: 0), velocityThreshold: 77)
        ],
        chordRules: [
            ChordMappingRule(notes: [60, 64, 67], output: KeyStroke(keyCode: 8, modifiers: [.command]))
        ]
    )

    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(MappingConfigPayload.self, from: data)
    #expect(decoded == payload)
}

@MainActor
@Test
func setSingleKeyMappingWritesKeyStrokeAndClampsNote() {
    var payload = MappingConfigPayload.empty
    payload.defaultVelocityThreshold = 88

    let context = makeEditorContext(payload: payload)

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

    let context = makeEditorContext(payload: payload)

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
    let context = makeEditorContext(payload: .empty)
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
    let context = makeEditorContext(payload: .empty)

    context.viewModel.createChordRule(notes: [], output: KeyStroke(keyCode: 8, modifiers: [.command]))

    #expect(context.viewModel.activeConfig?.payload.chordRules.isEmpty == true)
}

@MainActor
@Test
func mappingEditsPersistAfterRebootstrap() {
    var payload = MappingConfigPayload.empty
    payload.defaultVelocityThreshold = 92

    let context = makeEditorContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 60, keyCode: 0)
    context.viewModel.createChordRule(notes: [67, 60, 64], output: KeyStroke(keyCode: 8, modifiers: [.command]))

    let reloadedViewModel = makeEditorViewModel(configRepository: context.configRepository)
    reloadedViewModel.bootstrap()

    guard let activeConfig = reloadedViewModel.activeConfig else {
        Issue.record("Expected active config after rebootstrap")
        return
    }

    #expect(activeConfig.payload.singleKeyRules.contains(where: { $0.note == 60 && $0.output == KeyStroke(keyCode: 0) }))
    #expect(activeConfig.payload.chordRules.contains(where: { $0.notes == [60, 64, 67] && $0.output == KeyStroke(keyCode: 8, modifiers: [.command]) }))
}

@MainActor
private func makeEditorContext(payload: MappingConfigPayload) -> (
    viewModel: LonelyPianistViewModel,
    configRepository: MappingConfigRepositoryTestDouble
) {
    let config = MappingConfig(
        id: UUID(),
        updatedAt: Date(timeIntervalSince1970: 1000),
        payload: payload
    )

    let configRepository = MappingConfigRepositoryTestDouble(config: config)
    let viewModel = makeEditorViewModel(configRepository: configRepository)

    viewModel.bootstrap()

    return (viewModel, configRepository)
}

@MainActor
private func makeEditorViewModel(configRepository: MappingConfigRepositoryTestDouble) -> LonelyPianistViewModel {
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
    let dialogueService = DialogueServiceMock()
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
