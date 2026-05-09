import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class LonelyPianistViewModel {
    enum RecorderMode: Equatable {
        case idle
        case recording
        case playing
    }

    struct EventLogItem: Identifiable {
        let id = UUID()
        let timestamp: Date
        let title: String
        let detail: String
    }

    var isListening = false
    var connectionState: MIDIInputConnectionState = .idle
    var connectedSourceNames: [String] = []
    var midiEventCount = 0
    var statusMessage = "Ready"
    var recorderMode: RecorderMode = .idle
    var takes: [RecordingTake] = []
    var selectedTakeID: UUID?
    var playheadSec: TimeInterval = 0
    var recorderStatusMessage = "Recorder ready"
    var playbackOutputs: [MIDIPlaybackOutputOption] = []
    var selectedPlaybackOutputID: String = MIDIPlaybackOutputOption.builtInSamplerID
    var pressedNotes: [Int] = []
    var recentLogs: [EventLogItem] = []

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "ViewModel")

    private let midiInputService: MIDIInputServiceProtocol
    private let recordingRepository: RecordingTakeRepositoryProtocol
    private let recordingService: RecordingServiceProtocol
    private let playbackService: RoutableMIDIPlaybackServiceProtocol
    private var playbackClockTask: Task<Void, Never>?
    private var pendingSeekTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private var playbackOffsetSec: TimeInterval = 0

    init(
        midiInputService: MIDIInputServiceProtocol,
        recordingRepository: RecordingTakeRepositoryProtocol,
        recordingService: RecordingServiceProtocol,
        playbackService: RoutableMIDIPlaybackServiceProtocol
    ) {
        self.midiInputService = midiInputService
        self.recordingRepository = recordingRepository
        self.recordingService = recordingService
        self.playbackService = playbackService

        bindServiceCallbacks()
    }

    var selectedTake: RecordingTake? {
        guard let selectedTakeID else { return nil }
        return takes.first(where: { $0.id == selectedTakeID })
    }

    var canRecord: Bool {
        isListening && recorderMode != .playing
    }

    var canPlay: Bool {
        selectedTake != nil && recorderMode != .recording
    }

    var canStop: Bool {
        recorderMode != .idle
    }

    var connectionDescription: String {
        switch connectionState {
            case .idle:
                "Not Listening"
            case let .connected(sourceCount):
                sourceCount > 0 ? "Connected (\(sourceCount) source)" : "Listening (no source)"
            case let .failed(message):
                "Error: \(message)"
        }
    }

    func bootstrap() {
        do {
            try reloadTakes(preserveSelectedID: nil)
            refreshPlaybackOutputs()
        } catch {
            statusMessage = "Init failed: \(error.localizedDescription)"
            log(title: "Init Failed", detail: error.localizedDescription)
        }
    }

    func refreshPlaybackOutputs() {
        playbackService.refreshAvailableOutputs()
        playbackOutputs = playbackService.availableOutputs

        if playbackOutputs.contains(where: { $0.id == playbackService.selectedOutputID }) {
            selectedPlaybackOutputID = playbackService.selectedOutputID
        } else {
            selectedPlaybackOutputID = MIDIPlaybackOutputOption.builtInSamplerID
            playbackService.selectedOutputID = selectedPlaybackOutputID
        }
    }

    func setPlaybackOutput(id: String) {
        guard selectedPlaybackOutputID != id else { return }
        guard playbackOutputs.contains(where: { $0.id == id }) else { return }

        if recorderMode == .playing {
            stopTransport()
        }

        selectedPlaybackOutputID = id
        playbackService.selectedOutputID = id
        let title = playbackOutputs.first(where: { $0.id == id })?.title ?? "Unknown"
        recorderStatusMessage = "Output: \(title)"
        log(title: "Recorder", detail: "Playback output switched")
    }

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func startListening() {
        do {
            try midiInputService.start()
            isListening = true
            statusMessage = "Listening MIDI"
        } catch {
            isListening = false
            statusMessage = "Start failed: \(error.localizedDescription)"
            log(title: "Start Failed", detail: error.localizedDescription)
        }
    }

    func stopListening() {
        midiInputService.stop()
        isListening = false
        midiEventCount = 0
        pressedNotes.removeAll(keepingCapacity: false)
        statusMessage = "Stopped"
    }

    func refreshMIDISources() {
        do {
            try midiInputService.refreshSources()
            statusMessage = "MIDI sources refreshed"
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
            log(title: "MIDI Refresh Failed", detail: error.localizedDescription)
        }
    }

    func startRecordingTake() {
        guard canRecord else { return }

        if recorderMode == .playing {
            stopTransport()
        }

        guard recorderMode == .idle else { return }

        let now = Date()
        recordingService.startRecording(at: now)
        recorderMode = .recording
        playheadSec = 0
        recorderStatusMessage = "Recording..."
        statusMessage = "Recording take"
        log(title: "Recorder", detail: "Recording started")
    }

    func selectTake(_ id: UUID) {
        guard takes.contains(where: { $0.id == id }) else { return }

        if recorderMode == .playing {
            stopTransport()
        }

        selectedTakeID = id
        playheadSec = 0
        if let selectedTake {
            recorderStatusMessage = "Selected \(selectedTake.name)"
        }
    }

    func renameTake(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try recordingRepository.renameTake(id: id, name: trimmed)
            try reloadTakes(preserveSelectedID: id)
            recorderStatusMessage = "Take renamed"
            log(title: "Recorder", detail: "Take renamed: \(trimmed)")
        } catch {
            recorderStatusMessage = "Rename failed: \(error.localizedDescription)"
            log(title: "Recorder Rename Failed", detail: error.localizedDescription)
        }
    }

    func deleteTake(_ id: UUID) {
        if recorderMode == .playing, selectedTakeID == id {
            stopTransport()
        }

        do {
            try recordingRepository.deleteTake(id: id)
            let preserveID = selectedTakeID == id ? nil : selectedTakeID
            try reloadTakes(preserveSelectedID: preserveID)
            recorderStatusMessage = "Take deleted"
            log(title: "Recorder", detail: "Take deleted")
        } catch {
            recorderStatusMessage = "Delete failed: \(error.localizedDescription)"
            log(title: "Recorder Delete Failed", detail: error.localizedDescription)
        }
    }

    enum MIDIImportMode: Equatable {
        case all
        case pianoOnly
    }

    func importMIDIFile(from url: URL, mode: MIDIImportMode = .all) {
        guard recorderMode == .idle else { return }

        if url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            importMIDIFileInternal(from: url, mode: mode)
        } else {
            importMIDIFileInternal(from: url, mode: mode)
        }
    }

    private func importMIDIFileInternal(from url: URL, mode: MIDIImportMode) {
        do {
            let options: MIDIFileImportOptions = (mode == .pianoOnly) ? .pianoOnly : .default
            let (notes, durationSec) = try MIDIFileImporter.importNotes(from: url, options: options)

            let now = Date()
            let baseName = url.deletingPathExtension().lastPathComponent
            let name = baseName.isEmpty ? defaultTakeName(at: now) : baseName

            let take = RecordingTake(
                id: UUID(),
                name: name,
                createdAt: now,
                updatedAt: now,
                durationSec: durationSec,
                notes: notes
            )

            try recordingRepository.saveTake(take)
            try reloadTakes(preserveSelectedID: take.id)
            recorderStatusMessage = "Imported \(take.name)"
            statusMessage = "MIDI imported"
            log(title: "Recorder", detail: "MIDI imported: \(take.name)")
        } catch {
            recorderStatusMessage = "Import failed: \(error.localizedDescription)"
            statusMessage = "Import failed"
            log(title: "MIDI Import Failed", detail: error.localizedDescription)
        }
    }

    func playSelectedTake() {
        guard let selectedTake else { return }

        if recorderMode == .recording {
            stopTransport()
        }

        do {
            let offset = max(0, min(playheadSec, selectedTake.durationSec))
            try playbackService.play(take: selectedTake, fromOffsetSec: offset)
            recorderMode = .playing
            startPlaybackClock(fromOffsetSec: offset, durationSec: selectedTake.durationSec)
            recorderStatusMessage = "Playing \(selectedTake.name)"
            statusMessage = "Playing take"
            log(title: "Recorder", detail: "Playback started: \(selectedTake.name)")
        } catch {
            recorderStatusMessage = "Playback failed: \(error.localizedDescription)"
            statusMessage = "Playback failed"
            log(title: "Playback Failed", detail: error.localizedDescription)
        }
    }

    func seekPlayback(to seconds: TimeInterval) {
        guard let selectedTake else { return }

        let clamped = max(0, min(seconds, selectedTake.durationSec))
        playheadSec = clamped

        guard recorderMode == .playing else { return }

        pendingSeekTask?.cancel()
        pendingSeekTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            do {
                try playbackService.play(take: selectedTake, fromOffsetSec: clamped)
                startPlaybackClock(fromOffsetSec: clamped, durationSec: selectedTake.durationSec)
            } catch {
                recorderStatusMessage = "Seek failed: \(error.localizedDescription)"
                statusMessage = "Seek failed"
                log(title: "Seek Failed", detail: error.localizedDescription)
            }
        }
    }

    func stopTransport() {
        switch recorderMode {
            case .idle:
                return

            case .recording:
                let now = Date()
                let take = recordingService.stopRecording(
                    at: now,
                    takeID: UUID(),
                    name: defaultTakeName(at: now)
                )

                do {
                    if let take {
                        try recordingRepository.saveTake(take)
                        try reloadTakes(preserveSelectedID: take.id)
                        recorderStatusMessage = "Saved \(take.name)"
                        statusMessage = "Recording saved"
                        log(title: "Recorder", detail: "Recording saved: \(take.name)")
                    } else {
                        recorderStatusMessage = "Recording cancelled"
                        statusMessage = "Recording cancelled"
                        log(title: "Recorder", detail: "Recording cancelled")
                    }
                } catch {
                    recorderStatusMessage = "Save failed: \(error.localizedDescription)"
                    statusMessage = "Save failed"
                    log(title: "Recorder Save Failed", detail: error.localizedDescription)
                }

                recorderMode = .idle

            case .playing:
                playbackService.stop()
                pendingSeekTask?.cancel()
                pendingSeekTask = nil
                playbackClockTask?.cancel()
                playbackClockTask = nil
                playbackStartedAt = nil
                recorderMode = .idle
                recorderStatusMessage = "Playback stopped"
                statusMessage = "Playback stopped"
                log(title: "Recorder", detail: "Playback stopped")
        }
    }

    private func bindServiceCallbacks() {
        playbackService.onPlaybackFinished = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if recorderMode == .playing {
                    pendingSeekTask?.cancel()
                    pendingSeekTask = nil
                    playbackClockTask?.cancel()
                    playbackClockTask = nil
                    playbackStartedAt = nil

                    recorderMode = .idle
                    if let selectedTake {
                        playheadSec = selectedTake.durationSec
                    }
                    recorderStatusMessage = "Playback finished"
                    statusMessage = "Playback finished"
                }
            }
        }

        midiInputService.onConnectionStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.connectionState = state
            }
        }

        midiInputService.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMIDIEvent(event)
            }
        }

        midiInputService.onSourceNamesChange = { [weak self] names in
            Task { @MainActor [weak self] in
                self?.connectedSourceNames = names
            }
        }
    }

    private func handleMIDIEvent(_ event: MIDIEvent) {
        midiEventCount += 1
        updatePressedNotes(for: event)

        if recorderMode == .recording {
            recordingService.append(event: event)
        }
    }

    private func updatePressedNotes(for event: MIDIEvent) {
        switch event.type {
            case let .noteOn(note, velocity):
                if velocity == 0 {
                    pressedNotes.removeAll { $0 == note }
                } else if !pressedNotes.contains(note) {
                    pressedNotes.append(note)
                    pressedNotes.sort()
                }
            case let .noteOff(note, _):
                pressedNotes.removeAll { $0 == note }
            case .controlChange:
                return
        }
    }

    private func reloadTakes(preserveSelectedID: UUID?) throws {
        takes = try recordingRepository.fetchTakes()

        let preferredID = preserveSelectedID ?? selectedTakeID
        if let preferredID, takes.contains(where: { $0.id == preferredID }) {
            selectedTakeID = preferredID
        } else {
            selectedTakeID = takes.first?.id
        }

        playheadSec = 0
    }

    private func startPlaybackClock(fromOffsetSec offsetSec: TimeInterval, durationSec: TimeInterval) {
        playbackClockTask?.cancel()
        playbackClockTask = nil

        playbackStartedAt = .now
        playbackOffsetSec = offsetSec

        playbackClockTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard recorderMode == .playing, playbackService.isPlaying else { return }
                guard let playbackStartedAt else { return }

                let elapsed = Date().timeIntervalSince(playbackStartedAt)
                let current = min(durationSec, playbackOffsetSec + elapsed)
                playheadSec = current

                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func log(title: String, detail: String) {
        logger.info("\(title, privacy: .public): \(detail, privacy: .public)")

        recentLogs.insert(
            EventLogItem(timestamp: .now, title: title, detail: detail),
            at: 0
        )

        let maxLogCount = 50
        if recentLogs.count > maxLogCount {
            recentLogs.removeLast(recentLogs.count - maxLogCount)
        }
    }

    private func defaultTakeName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "Take \(formatter.string(from: date))"
    }

    // Rule normalization removed (mappings are no longer supported).
}
