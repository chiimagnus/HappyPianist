import AppKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class LonelyPianistViewModel {
    enum MainWindowSection: String, CaseIterable, Identifiable {
        case runtime = "Runtime"
        case mappings = "Mappings"
        case recorder = "Recorder"
        case dialogue = "Dialogue"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .runtime:
                return "gauge"
            case .mappings:
                return "slider.horizontal.3"
            case .recorder:
                return "waveform"
            case .dialogue:
                return "bubble.left.and.bubble.right"
            }
        }
    }

    enum EditorTab: String, CaseIterable, Identifiable {
        case singleKey = "Single Key"
        case chord = "Chord"

        var id: String { rawValue }
    }

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
    var hasAccessibilityPermission = false
    var statusMessage = "Ready"

    var activeConfig: MappingConfig?

    var selectedMainWindowSection: MainWindowSection = .runtime
    var selectedTab: EditorTab = .singleKey
    var recorderMode: RecorderMode = .idle
    var takes: [RecordingTake] = []
    var selectedTakeID: UUID?
    var playheadSec: TimeInterval = 0
    var recorderStatusMessage = "Recorder ready"
    var playbackOutputs: [MIDIPlaybackOutputOption] = []
    var selectedPlaybackOutputID: String = MIDIPlaybackOutputOption.builtInSamplerID
    var previewText = ""
    var pressedNotes: [Int] = []
    var recentLogs: [EventLogItem] = []

    var dialogueStatus: DialogueManager.Status = .idle
    var dialogueLatencyMs: Int?
    var dialoguePlaybackInterruptionBehavior: DialoguePlaybackInterruptionBehavior = .interrupt {
        didSet {
            UserDefaults.standard.set(dialoguePlaybackInterruptionBehavior.rawValue, forKey: DialoguePlaybackInterruptionBehavior.userDefaultsKey)
            dialogueManager.playbackInterruptionBehavior = dialoguePlaybackInterruptionBehavior
        }
    }

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "ViewModel")

    private let midiInputService: MIDIInputServiceProtocol
    private let keyboardEventService: KeyboardEventServiceProtocol
    private let permissionService: PermissionServiceProtocol
    private let repository: MappingConfigRepositoryProtocol
    private let recordingRepository: RecordingTakeRepositoryProtocol
    private let recordingService: RecordingServiceProtocol
    private let playbackService: RoutableMIDIPlaybackServiceProtocol
    private let mappingEngine: MappingEngineProtocol
    private let shortcutService: ShortcutServiceProtocol
    private let dialogueManager: DialogueManager
    private var permissionPollingTask: Task<Void, Never>?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var playbackClockTask: Task<Void, Never>?
    private var pendingSeekTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private var playbackOffsetSec: TimeInterval = 0

    init(
        midiInputService: MIDIInputServiceProtocol,
        keyboardEventService: KeyboardEventServiceProtocol,
        permissionService: PermissionServiceProtocol,
        repository: MappingConfigRepositoryProtocol,
        recordingRepository: RecordingTakeRepositoryProtocol,
        recordingService: RecordingServiceProtocol,
        playbackService: RoutableMIDIPlaybackServiceProtocol,
        mappingEngine: MappingEngineProtocol,
        shortcutService: ShortcutServiceProtocol,
        dialogueManager: DialogueManager
    ) {
        self.midiInputService = midiInputService
        self.keyboardEventService = keyboardEventService
        self.permissionService = permissionService
        self.repository = repository
        self.recordingRepository = recordingRepository
        self.recordingService = recordingService
        self.playbackService = playbackService
        self.mappingEngine = mappingEngine
        self.shortcutService = shortcutService
        self.dialogueManager = dialogueManager

        bindServiceCallbacks()
        bindAppLifecycleCallbacks()

        let behaviorRaw = UserDefaults.standard.string(forKey: DialoguePlaybackInterruptionBehavior.userDefaultsKey)
        dialoguePlaybackInterruptionBehavior = DialoguePlaybackInterruptionBehavior(rawValue: behaviorRaw ?? "") ?? .interrupt

        dialogueStatus = dialogueManager.status
        dialogueManager.onStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.dialogueStatus = status
            }
        }
        dialogueManager.onLatencyChange = { [weak self] latencyMs in
            Task { @MainActor [weak self] in
                self?.dialogueLatencyMs = latencyMs
            }
        }

        dialogueManager.onSessionTakeSaved = { [weak self] takeID in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let preserveID = selectedTakeID ?? takeID
                    try reloadTakes(preserveSelectedID: preserveID)
                } catch {
                    log(title: "Dialogue Save", detail: error.localizedDescription)
                }
            }
        }
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
            return "Not Listening"
        case .connected(let sourceCount):
            return sourceCount > 0 ? "Connected (\(sourceCount) source)" : "Listening (no source)"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

    func bootstrap() {
        hasAccessibilityPermission = permissionService.hasAccessibilityPermission()

        do {
            try repository.ensureSeedConfigIfNeeded()
            try reloadConfig()
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
        hasAccessibilityPermission = permissionService.hasAccessibilityPermission()

        guard hasAccessibilityPermission else {
            statusMessage = "Accessibility permission is required"
            log(title: "Permission", detail: "Accessibility permission missing")
            return
        }

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
        if dialogueManager.isActive {
            dialogueManager.stop()
        }
        midiInputService.stop()
        mappingEngine.reset()
        isListening = false
        midiEventCount = 0
        pressedNotes.removeAll(keepingCapacity: false)
        statusMessage = "Stopped"
    }

    func startDialogue() {
        guard isListening else {
            statusMessage = "Start listening before Dialogue"
            return
        }

        guard recorderMode == .idle else {
            statusMessage = "Stop Recorder before Dialogue"
            return
        }

        guard !playbackService.isPlaying else {
            statusMessage = "Stop playback before Dialogue"
            return
        }

        dialogueManager.playbackInterruptionBehavior = dialoguePlaybackInterruptionBehavior
        dialogueManager.start()
        statusMessage = "Dialogue started"
    }

    func stopDialogue() {
        dialogueManager.stop()
        statusMessage = "Dialogue stopped"
    }

    func requestAccessibilityPermission() {
        permissionPollingTask?.cancel()
        permissionPollingTask = nil

        hasAccessibilityPermission = permissionService.requestAccessibilityPermission()

        if hasAccessibilityPermission {
            statusMessage = "Accessibility enabled"
            log(title: "Permission", detail: "Accessibility granted")
            return
        }

        statusMessage = "Waiting for Accessibility authorization..."
        log(title: "Permission", detail: "Authorization requested")

        // Poll for up to 60s so granting in System Settings updates immediately without app restart.
        permissionPollingTask = Task { [weak self] in
            guard let self else { return }
            var openedSettings = false

            for attempt in 0..<120 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                let granted = permissionService.hasAccessibilityPermission()
                hasAccessibilityPermission = granted

                if granted {
                    statusMessage = "Accessibility enabled"
                    log(title: "Permission", detail: "Accessibility granted")
                    permissionPollingTask = nil
                    return
                }

                if !openedSettings, attempt == 11 {
                    statusMessage = "Open System Settings > Privacy & Security > Accessibility and enable LonelyPianist"
                    log(title: "Permission", detail: "No grant detected, opening System Settings")
                    permissionService.openAccessibilitySettings()
                    openedSettings = true
                }
            }

            if !openedSettings {
                statusMessage = "Open System Settings > Privacy & Security > Accessibility and enable LonelyPianist"
                log(title: "Permission", detail: "No grant detected, opening System Settings")
                permissionService.openAccessibilitySettings()
            }

            permissionPollingTask = nil
        }
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
        if recorderMode == .playing && selectedTakeID == id {
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

    enum MIDIImportMode: Sendable, Equatable {
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

    func setVelocityEnabled(_ enabled: Bool) {
        mutateActiveConfig { config in
            config.payload.velocityEnabled = enabled
        }
    }

    func setVelocityThreshold(_ value: Int) {
        mutateActiveConfig { config in
            config.payload.defaultVelocityThreshold = max(1, min(127, value))
        }
    }

    func setSingleKeyMapping(note: Int, keyCode: UInt16) {
        let clampedNote = max(0, min(127, note))

        mutateActiveConfig { config in
            let existingForNote = config.payload.singleKeyRules.filter { $0.note == clampedNote }
            let selectedExisting = existingForNote.last

            config.payload.singleKeyRules.removeAll { $0.note == clampedNote }

            if var selectedExisting {
                selectedExisting.note = clampedNote
                selectedExisting.output = KeyStroke(keyCode: keyCode)
                config.payload.singleKeyRules.append(selectedExisting)
            } else {
                config.payload.singleKeyRules.append(
                    SingleKeyMappingRule(
                        note: clampedNote,
                        output: KeyStroke(keyCode: keyCode),
                        velocityThreshold: config.payload.defaultVelocityThreshold
                    )
                )
            }
        }
    }

    func setSingleKeyMapping(note: Int, output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let token = trimmed.first, let keyCode = KeyStroke.keyCode(for: token) else {
            return
        }
        setSingleKeyMapping(note: note, keyCode: keyCode)
    }

    func createChordRule(notes: [Int], output: KeyStroke) {
        let normalizedNotes = Self.normalizeRuleNotes(notes)
        guard !normalizedNotes.isEmpty else { return }

        mutateActiveConfig { config in
            config.payload.chordRules.append(
                ChordMappingRule(notes: normalizedNotes, output: output)
            )
        }
    }

    func updateChordRule(_ rule: ChordMappingRule) {
        mutateActiveConfig { config in
            guard let index = config.payload.chordRules.firstIndex(where: { $0.id == rule.id }) else { return }
            var normalizedRule = rule
            normalizedRule.notes = Self.normalizeRuleNotes(rule.notes)
            config.payload.chordRules[index] = normalizedRule
        }
    }

    private func removeChordRule(_ ruleID: UUID) {
        mutateActiveConfig { config in
            config.payload.chordRules.removeAll { $0.id == ruleID }
        }
    }

    func deleteChordRule(id: UUID) {
        removeChordRule(id)
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

                dialogueManager.notifyPlaybackFinished()
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

    private func bindAppLifecycleCallbacks() {
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityPermissionAfterAppActivation()
            }
        }
    }

    private func refreshAccessibilityPermissionAfterAppActivation() {
        let granted = permissionService.hasAccessibilityPermission()
        let hadPermission = hasAccessibilityPermission
        hasAccessibilityPermission = granted

        guard granted, !hadPermission else { return }

        permissionPollingTask?.cancel()
        permissionPollingTask = nil
        statusMessage = "Accessibility enabled"
        log(title: "Permission", detail: "Accessibility granted")
    }

    private func handleMIDIEvent(_ event: MIDIEvent) {
        midiEventCount += 1
        updatePressedNotes(for: event)

        if dialogueManager.isActive {
            dialogueManager.handle(event: event)
            return
        }

        if recorderMode == .recording {
            recordingService.append(event: event)
        }

        guard let activeConfig else { return }

        let resolvedActions = mappingEngine.process(event: event, payload: activeConfig.payload)

        for resolvedAction in resolvedActions {
            do {
                try execute(resolvedAction.keyStroke)
                appendPreview("[\(resolvedAction.keyStroke.displayLabel)]")

                log(
                    title: "\(resolvedAction.triggerType)",
                    detail: "\(resolvedAction.sourceDescription) -> \(resolvedAction.keyStroke.displayLabel)"
                )
            } catch {
                statusMessage = "Action failed: \(error.localizedDescription)"
                log(title: "Action Failed", detail: error.localizedDescription)
            }
        }

        if resolvedActions.isEmpty {
            switch event.type {
            case .noteOn(let note, let velocity):
                let noteName = MIDINote(note).name
                log(title: "MIDI", detail: "noteOn \(noteName) velocity \(velocity)")
            case .noteOff(let note, let velocity):
                let noteName = MIDINote(note).name
                log(title: "MIDI", detail: "noteOff \(noteName) velocity \(velocity)")
            case .controlChange(let controller, let value):
                log(title: "MIDI", detail: "cc \(controller) value \(value)")
            }
        }
    }

    private func execute(_ keyStroke: KeyStroke) throws {
        try keyboardEventService.sendKeyCombo(
            keyCode: CGKeyCode(keyStroke.keyCode),
            modifiers: keyStroke.modifiers.cgEventFlags
        )
    }

    private func updatePressedNotes(for event: MIDIEvent) {
        switch event.type {
        case .noteOn(let note, let velocity):
            if velocity == 0 {
                pressedNotes.removeAll { $0 == note }
            } else if !pressedNotes.contains(note) {
                pressedNotes.append(note)
                pressedNotes.sort()
            }
        case .noteOff(let note, _):
            pressedNotes.removeAll { $0 == note }
        case .controlChange:
            return
        }
    }

    private func appendPreview(_ text: String) {
        previewText += text
        if previewText.count > 120 {
            previewText = String(previewText.suffix(120))
        }
    }

    private func mutateActiveConfig(_ mutation: (inout MappingConfig) -> Void) {
        guard var config = activeConfig else { return }

        mutation(&config)
        config.updatedAt = .now

        do {
            try repository.saveConfig(config)
            activeConfig = try repository.fetchConfig()
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
            log(title: "Update Failed", detail: error.localizedDescription)
        }
    }

    private func reloadConfig() throws {
        activeConfig = try repository.fetchConfig()
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

    nonisolated private static func normalizeRuleNotes(_ notes: [Int]) -> [Int] {
        Array(
            Set(notes.map { max(0, min(127, $0)) })
        ).sorted()
    }
}
