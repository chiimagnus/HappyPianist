import CoreGraphics
import Foundation
@testable import LonelyPianist

@MainActor
final class MIDIInputServiceMock: MIDIInputServiceProtocol {
    var onEvent: (@Sendable (MIDIEvent) -> Void)?
    var onConnectionStateChange: (@Sendable (MIDIInputConnectionState) -> Void)?
    var onSourceNamesChange: (@Sendable ([String]) -> Void)?

    func start() throws {}
    func stop() {}
    func refreshSources() throws {}
}

@MainActor
final class KeyboardEventServiceMock: KeyboardEventServiceProtocol {
    private(set) var typedTexts: [String] = []
    private(set) var keyCombos: [(CGKeyCode, CGEventFlags)] = []
    private(set) var keyStrokes: [KeyStroke] = []

    func typeText(_ text: String) throws {
        typedTexts.append(text)
    }

    func sendKeyStroke(_ keyStroke: KeyStroke) throws {
        keyStrokes.append(keyStroke)
        keyCombos.append((CGKeyCode(keyStroke.keyCode), keyStroke.modifiers.cgEventFlags))
    }
}

@MainActor
final class PermissionServiceMock: PermissionServiceProtocol {
    var permissionGranted = true

    func hasAccessibilityPermission() -> Bool {
        permissionGranted
    }

    func requestAccessibilityPermission() -> Bool {
        permissionGranted
    }

    func openAccessibilitySettings() {}
}

@MainActor
final class MappingConfigRepositoryMock: MappingConfigRepositoryProtocol {
    var config: MappingConfig = .init(
        id: UUID(),
        updatedAt: .now,
        payload: .empty
    )

    func ensureSeedConfigIfNeeded() throws {}

    func fetchConfig() throws -> MappingConfig {
        config
    }

    func saveConfig(_ config: MappingConfig) throws {
        self.config = config
    }
}

@MainActor
final class RecordingTakeRepositoryMock: RecordingTakeRepositoryProtocol {
    var takes: [RecordingTake] = []
    var error: Error?

    private(set) var savedTakes: [RecordingTake] = []

    func fetchTakes() throws -> [RecordingTake] {
        if let error { throw error }
        return takes
    }

    func saveTake(_ take: RecordingTake) throws {
        if let error { throw error }
        savedTakes.append(take)
        if let index = takes.firstIndex(where: { $0.id == take.id }) {
            takes[index] = take
        } else {
            takes.append(take)
        }
    }

    func deleteTake(id: UUID) throws {
        if let error { throw error }
        takes.removeAll { $0.id == id }
    }

    func renameTake(id: UUID, name: String) throws {
        if let error { throw error }
        guard let index = takes.firstIndex(where: { $0.id == id }) else { return }
        takes[index].name = name
        takes[index].updatedAt = .now
    }
}

final class RecordingServiceMock: RecordingServiceProtocol {
    var isRecording = false
    var startedAt: Date?

    var nextStoppedTake: RecordingTake?
    private(set) var appendedEvents: [MIDIEvent] = []

    func startRecording(at date: Date) {
        startedAt = date
        isRecording = true
    }

    func append(event: MIDIEvent) {
        appendedEvents.append(event)
    }

    func stopRecording(at date: Date, takeID: UUID, name: String) -> RecordingTake? {
        isRecording = false
        defer { nextStoppedTake = nil }

        if var take = nextStoppedTake {
            take.id = takeID
            take.name = name
            take.updatedAt = date
            return take
        }

        return nil
    }

    func cancelRecording() {
        isRecording = false
    }
}

@MainActor
final class MIDIPlaybackServiceMock: RoutableMIDIPlaybackServiceProtocol {
    var isPlaying = false
    var onPlaybackFinished: (@Sendable () -> Void)?
    var playError: Error?

    var availableOutputs: [MIDIPlaybackOutputOption] = [
        MIDIPlaybackOutputOption(
            id: MIDIPlaybackOutputOption.builtInSamplerID,
            title: "Built-in Sampler",
            kind: .builtInSampler
        ),
    ]
    var selectedOutputID: String = MIDIPlaybackOutputOption.builtInSamplerID

    private(set) var playedTakes: [RecordingTake] = []
    private(set) var playedOffsets: [TimeInterval] = []

    func refreshAvailableOutputs() {}

    func play(take: RecordingTake) throws {
        try play(take: take, fromOffsetSec: 0)
    }

    func play(take: RecordingTake, fromOffsetSec offsetSec: TimeInterval) throws {
        if let playError { throw playError }
        playedTakes.append(take)
        playedOffsets.append(offsetSec)
        isPlaying = true
    }

    func stop() {
        isPlaying = false
    }
}

@MainActor
final class MappingEngineMock: MappingEngineProtocol {
    func process(event _: MIDIEvent, payload _: MappingConfigPayload) -> [ResolvedKeyStroke] {
        []
    }

    func reset() {}
}

@MainActor
final class ShortcutServiceMock: ShortcutServiceProtocol {
    func runShortcut(named _: String) throws {}
}

@MainActor
final class DialogueServiceMock: DialogueServiceProtocol {
    var connectionState: DialogueServiceConnectionState = .disconnected {
        didSet { onConnectionStateChange?(connectionState) }
    }

    var onConnectionStateChange: (@Sendable (DialogueServiceConnectionState) -> Void)?

    func connect(url _: URL) {
        connectionState = .connected
    }

    func disconnect() {
        connectionState = .disconnected
    }

    func generate(
        notes _: [DialogueNote],
        params _: DialogueGenerateParams,
        sessionID _: String?
    ) async throws -> (notes: [DialogueNote], latencyMs: Int?) {
        ([], nil)
    }
}

struct ClockMock: ClockProtocol {
    let nowValue: Date

    func now() -> Date {
        nowValue
    }
}

struct DummyError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
