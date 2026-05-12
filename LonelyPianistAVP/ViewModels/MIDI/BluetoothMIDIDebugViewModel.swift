import Foundation
import Observation

@MainActor
@Observable
final class BluetoothMIDIDebugViewModel {
    private let inputService: CoreMIDIDebugInputService

    var sourceNames: [String] = []
    var statusText = "idle"
    var noteOnCount = 0
    var noteOffCount = 0
    var lastNoteText: String?

    init(inputService: CoreMIDIDebugInputService? = nil) {
        let inputService = inputService ?? CoreMIDIDebugInputService()
        self.inputService = inputService

        inputService.onSourceNamesChange = { [weak self] names in
            Task { @MainActor [weak self] in
                self?.sourceNames = names
            }
        }

        inputService.onStatusTextChange = { [weak self] text in
            Task { @MainActor [weak self] in
                self?.statusText = text
            }
        }

        inputService.onNoteEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleNoteEvent(event)
            }
        }
    }

    func start() {
        do {
            try inputService.start()
        } catch {
            statusText = error.localizedDescription
        }
    }

    func stop() {
        inputService.stop()
    }

    func refreshSources() {
        do {
            try inputService.refreshSources()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func handleNoteEvent(_ event: CoreMIDIDebugInputService.NoteEvent) {
        switch event.kind {
            case let .noteOn(note, velocity):
                noteOnCount += 1
                lastNoteText = "noteOn ch\(event.channel) n\(note) v\(velocity)"
            case let .noteOff(note, velocity):
                noteOffCount += 1
                lastNoteText = "noteOff ch\(event.channel) n\(note) v\(velocity)"
        }
    }
}
