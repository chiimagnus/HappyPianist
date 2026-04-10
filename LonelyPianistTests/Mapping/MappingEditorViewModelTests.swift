import Foundation
import Testing
@testable import LonelyPianist

@MainActor
@Test
func setSingleKeyMappingWritesUppercaseAndClampsNote() {
    var payload = MappingProfilePayload.empty
    payload.defaultVelocityThreshold = 88

    let context = makeContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 188, output: "k")

    guard let activeProfile = context.viewModel.activeProfile,
          let rule = activeProfile.payload.singleKeyRules.first(where: { $0.note == 127 }) else {
        Issue.record("Expected a single-key rule at note 127")
        return
    }

    #expect(rule.normalOutput == "k")
    #expect(rule.highVelocityOutput == "K")
    #expect(rule.velocityThreshold == 88)
}

@MainActor
@Test
func setSingleKeyMappingTrimsNewlinesAndUppercases() {
    let context = makeContext(payload: .empty)

    context.viewModel.setSingleKeyMapping(note: 60, output: "\n\nq\n")

    guard let activeProfile = context.viewModel.activeProfile,
          let rule = activeProfile.payload.singleKeyRules.first(where: { $0.note == 60 }) else {
        Issue.record("Expected a single-key rule at note 60")
        return
    }

    #expect(rule.normalOutput == "q")
    #expect(rule.highVelocityOutput == "Q")
}

@MainActor
@Test
func setSingleKeyMappingKeepsOnlyOneRulePerNote() {
    let duplicatedRules: [SingleKeyMappingRule] = [
        SingleKeyMappingRule(
            note: 60,
            normalOutput: "x",
            velocityThreshold: 70,
            highVelocityOutput: "X"
        ),
        SingleKeyMappingRule(
            note: 60,
            normalOutput: "y",
            velocityThreshold: 111,
            highVelocityOutput: "Y"
        )
    ]

    let payload = MappingProfilePayload(
        velocityEnabled: true,
        defaultVelocityThreshold: 90,
        singleKeyRules: duplicatedRules,
        chordRules: [],
        melodyRules: []
    )

    let context = makeContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 60, output: "q")

    guard let activeProfile = context.viewModel.activeProfile else {
        Issue.record("Missing active profile")
        return
    }

    let rulesAtNote60 = activeProfile.payload.singleKeyRules.filter { $0.note == 60 }
    #expect(rulesAtNote60.count == 1)
    #expect(rulesAtNote60.first?.normalOutput == "q")
    #expect(rulesAtNote60.first?.highVelocityOutput == "Q")
    #expect(rulesAtNote60.first?.velocityThreshold == 111)
}

@MainActor
@Test
func chordCrudNormalizesNotesAndPersists() {
    let context = makeContext(payload: .empty)

    context.viewModel.createChordRule(notes: [67, 60, 67, 64], action: .text("copy"))

    guard let created = context.viewModel.activeProfile?.payload.chordRules.first else {
        Issue.record("Expected one chord rule after creation")
        return
    }

    #expect(created.notes == [60, 64, 67])
    #expect(created.action == .text("copy"))

    var updated = created
    updated.notes = [69, 62, 69]
    updated.action = .shortcut("Open Notion")
    context.viewModel.updateChordRule(updated)

    guard let updatedRule = context.viewModel.activeProfile?.payload.chordRules.first(where: { $0.id == created.id }) else {
        Issue.record("Expected updated chord rule")
        return
    }

    #expect(updatedRule.notes == [62, 69])
    #expect(updatedRule.action == .shortcut("Open Notion"))

    context.viewModel.deleteChordRule(id: created.id)
    #expect(context.viewModel.activeProfile?.payload.chordRules.isEmpty == true)
}

@MainActor
@Test
func createChordRuleIgnoresEmptyNotes() {
    let context = makeContext(payload: .empty)

    context.viewModel.createChordRule(notes: [], action: .text("noop"))

    #expect(context.viewModel.activeProfile?.payload.chordRules.isEmpty == true)
}

@MainActor
@Test
func melodyCrudPersistsSequenceAndInterval() {
    let context = makeContext(payload: .empty)

    context.viewModel.createMelodyRule(
        notes: [60, 129, -1, 62],
        maxIntervalMilliseconds: 90,
        action: .text("mel")
    )

    guard let created = context.viewModel.activeProfile?.payload.melodyRules.first else {
        Issue.record("Expected one melody rule after creation")
        return
    }

    #expect(created.notes == [60, 127, 0, 62])
    #expect(created.maxIntervalMilliseconds == 100)
    #expect(created.action == .text("mel"))

    var updated = created
    updated.notes = [65, 64]
    updated.maxIntervalMilliseconds = 240
    updated.action = .keyCombo("cmd+k")
    context.viewModel.updateMelodyRule(updated)

    guard let updatedRule = context.viewModel.activeProfile?.payload.melodyRules.first(where: { $0.id == created.id }) else {
        Issue.record("Expected updated melody rule")
        return
    }

    #expect(updatedRule.notes == [65, 64])
    #expect(updatedRule.maxIntervalMilliseconds == 240)
    #expect(updatedRule.action == .keyCombo("cmd+k"))

    context.viewModel.deleteMelodyRule(id: created.id)
    #expect(context.viewModel.activeProfile?.payload.melodyRules.isEmpty == true)
}

@MainActor
@Test
func createMelodyRuleIgnoresEmptyNotes() {
    let context = makeContext(payload: .empty)

    context.viewModel.createMelodyRule(notes: [], maxIntervalMilliseconds: 200, action: .text("noop"))

    #expect(context.viewModel.activeProfile?.payload.melodyRules.isEmpty == true)
}

@MainActor
@Test
func createMelodyRuleClampsLowerBoundInterval() {
    let context = makeContext(payload: .empty)

    context.viewModel.createMelodyRule(notes: [60, 62], maxIntervalMilliseconds: -500, action: .text("mel"))

    guard let created = context.viewModel.activeProfile?.payload.melodyRules.first else {
        Issue.record("Expected one melody rule after creation")
        return
    }

    #expect(created.maxIntervalMilliseconds == 100)
}

@MainActor
@Test
func mappingEditsPersistAfterRebootstrap() {
    var payload = MappingProfilePayload.empty
    payload.defaultVelocityThreshold = 92

    let context = makeContext(payload: payload)

    context.viewModel.setSingleKeyMapping(note: 60, output: "a")
    context.viewModel.createChordRule(notes: [67, 60, 64], action: .text("copy"))
    context.viewModel.createMelodyRule(notes: [60, 62, 64], maxIntervalMilliseconds: 300, action: .text("mel"))

    let reloadedViewModel = makeViewModel(profileRepository: context.profileRepository)
    reloadedViewModel.bootstrap()

    guard let activeProfile = reloadedViewModel.activeProfile else {
        Issue.record("Expected active profile after rebootstrap")
        return
    }

    #expect(activeProfile.payload.singleKeyRules.contains(where: { $0.note == 60 && $0.normalOutput == "a" }))
    #expect(activeProfile.payload.chordRules.contains(where: { $0.notes == [60, 64, 67] && $0.action == .text("copy") }))
    #expect(activeProfile.payload.melodyRules.contains(where: { $0.notes == [60, 62, 64] && $0.maxIntervalMilliseconds == 300 }))
}

@MainActor
private func makeContext(payload: MappingProfilePayload) -> (
    viewModel: LonelyPianistViewModel,
    profileRepository: MappingProfileRepositoryTestDouble
) {
    let profile = MappingProfile(
        id: UUID(),
        name: "Test Profile",
        isBuiltIn: false,
        isActive: true,
        createdAt: Date(timeIntervalSince1970: 1000),
        updatedAt: Date(timeIntervalSince1970: 1000),
        payload: payload
    )

    let profileRepository = MappingProfileRepositoryTestDouble(profiles: [profile])
    let viewModel = makeViewModel(profileRepository: profileRepository)

    viewModel.bootstrap()

    return (viewModel, profileRepository)
}

@MainActor
private func makeViewModel(profileRepository: MappingProfileRepositoryTestDouble) -> LonelyPianistViewModel {
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
        repository: profileRepository,
        recordingRepository: recordingRepository,
        recordingService: recordingService,
        playbackService: playback,
        mappingEngine: mapping,
        shortcutService: shortcut,
        dialogueManager: dialogueManager
    )
}
