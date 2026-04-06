import Foundation
import OSLog

@MainActor
final class DialogueManager {
    enum Status: String, Equatable, Sendable {
        case idle
        case listening
        case thinking
        case playing
    }

    private struct NoteKey: Hashable {
        let note: Int
        let channel: Int
    }

    private struct OpenNote {
        let startedAt: Date
        let velocity: Int
    }

    var onStatusChange: (@Sendable (Status) -> Void)?
    var onLatencyChange: (@Sendable (Int?) -> Void)?
    var onSessionTakeSaved: (@Sendable (UUID) -> Void)?

    private(set) var status: Status = .idle {
        didSet { onStatusChange?(status) }
    }

    private(set) var lastLatencyMs: Int? {
        didSet { onLatencyChange?(lastLatencyMs) }
    }

    var playbackInterruptionBehavior: DialoguePlaybackInterruptionBehavior = .interrupt

    private let logger = Logger(subsystem: "com.chiimagnus.LonelyPianist", category: "Dialogue")

    private let clock: ClockProtocol
    private let silenceDetectionService: SilenceDetectionServiceProtocol
    private let dialogueService: DialogueServiceProtocol
    private let recordingRepository: RecordingTakeRepositoryProtocol
    private let playbackService: MIDIPlaybackServiceProtocol

    private let serverURL = URL(string: "ws://127.0.0.1:8765/ws")!

    private var sessionID: String?
    private var sessionStartedAt: Date?
    private var sessionTakeID: UUID?
    private var sessionTakeName: String?
    private var sessionNotes: [RecordedNote] = []

    private var openNotes: [NoteKey: OpenNote] = [:]

    private var phraseStartedAt: Date?
    private var phraseNotes: [DialogueNote] = []

    private var queuedPhrases: [[DialogueNote]] = []

    private var pollingTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?
    private var currentAIPlaybackStartedAt: Date?

    init(
        clock: ClockProtocol,
        silenceDetectionService: SilenceDetectionServiceProtocol,
        dialogueService: DialogueServiceProtocol,
        recordingRepository: RecordingTakeRepositoryProtocol,
        playbackService: MIDIPlaybackServiceProtocol
    ) {
        self.clock = clock
        self.silenceDetectionService = silenceDetectionService
        self.dialogueService = dialogueService
        self.recordingRepository = recordingRepository
        self.playbackService = playbackService
    }

    var isActive: Bool {
        status != .idle
    }

    func start() {
        guard status == .idle else { return }

        let startedAt = clock.now()
        let id = UUID()
        sessionID = UUID().uuidString
        sessionStartedAt = startedAt
        sessionTakeID = id
        sessionTakeName = "Dialogue \(formatted(date: startedAt))"
        sessionNotes.removeAll(keepingCapacity: false)
        openNotes.removeAll(keepingCapacity: false)
        resetPhraseCollection()
        queuedPhrases.removeAll(keepingCapacity: false)

        silenceDetectionService.reset()
        dialogueService.connect(url: serverURL)
        lastLatencyMs = nil

        status = .listening
        startPolling()
        logger.info("Dialogue started")
    }

    func stop() {
        guard status != .idle else { return }

        pollingTask?.cancel()
        pollingTask = nil
        generationTask?.cancel()
        generationTask = nil

        if playbackService.isPlaying {
            playbackService.stop()
        }

        dialogueService.disconnect()

        if !sessionNotes.isEmpty {
            saveSessionTake(updatedAt: clock.now())
        }

        sessionID = nil
        sessionStartedAt = nil
        sessionTakeID = nil
        sessionTakeName = nil
        sessionNotes.removeAll(keepingCapacity: false)
        openNotes.removeAll(keepingCapacity: false)
        queuedPhrases.removeAll(keepingCapacity: false)
        resetPhraseCollection()

        lastLatencyMs = nil
        status = .idle
        logger.info("Dialogue stopped")
    }

    func handle(event: MIDIEvent) {
        guard status != .idle else { return }

        switch status {
        case .playing:
            switch playbackInterruptionBehavior {
            case .ignore:
                return
            case .interrupt:
                if case .noteOn = event.type {
                    stopAIPlaybackAndReturnToListening()
                }
            case .queue:
                break
            }
        case .thinking:
            // Keep it simple for P3: ignore input while thinking.
            return
        default:
            break
        }

        silenceDetectionService.handle(event: event)

        switch event.type {
        case .noteOn(let note, let velocity):
            if phraseStartedAt == nil {
                phraseStartedAt = event.timestamp
            }

            let key = NoteKey(note: note, channel: event.channel)
            if let openNote = openNotes[key] {
                appendHumanNote(
                    note: note,
                    velocity: openNote.velocity,
                    channel: event.channel,
                    startAt: openNote.startedAt,
                    endAt: event.timestamp
                )
            }
            openNotes[key] = OpenNote(startedAt: event.timestamp, velocity: velocity)

        case .noteOff(let note, _):
            let key = NoteKey(note: note, channel: event.channel)
            guard let openNote = openNotes.removeValue(forKey: key) else { return }
            appendHumanNote(
                note: note,
                velocity: openNote.velocity,
                channel: event.channel,
                startAt: openNote.startedAt,
                endAt: event.timestamp
            )

        case .controlChange:
            return
        }
    }

    func notifyPlaybackFinished() {
        guard status == .playing else { return }
        didFinishAIPlayback()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                self.pollSilence()
            }
        }
    }

    private func pollSilence() {
        guard status != .idle else { return }

        if status == .listening || (status == .playing && playbackInterruptionBehavior == .queue) {
            guard silenceDetectionService.pollSilenceDetected() else { return }
            guard !phraseNotes.isEmpty else {
                resetPhraseCollection()
                return
            }

            let phrase = phraseNotes.sorted(by: { $0.time < $1.time })
            resetPhraseCollection()

            if status == .playing && playbackInterruptionBehavior == .queue {
                queuedPhrases.append(phrase)
                return
            }

            startGeneration(for: phrase)
        }
    }

    private func startGeneration(for phrase: [DialogueNote]) {
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            await self.runGeneration(for: phrase)
        }
    }

    private func runGeneration(for phrase: [DialogueNote]) async {
        guard status == .listening else { return }
        guard let sessionID else { return }

        status = .thinking

        do {
            let params = DialogueGenerateParams()
            let result = try await dialogueService.generate(notes: phrase, params: params, sessionID: sessionID)
            lastLatencyMs = result.latencyMs
            await playAIReply(notes: result.notes)
        } catch {
            logger.error("Dialogue generate failed: \(error.localizedDescription, privacy: .public)")
            status = .listening
        }
    }

    private func playAIReply(notes: [DialogueNote]) async {
        guard let sessionStartedAt else { return }
        let playbackStartedAt = clock.now()
        currentAIPlaybackStartedAt = playbackStartedAt

        let recorded = notes.map { note in
            RecordedNote(
                id: UUID(),
                note: note.note,
                velocity: note.velocity,
                channel: 4,
                startOffsetSec: max(0, playbackStartedAt.timeIntervalSince(sessionStartedAt) + note.time),
                durationSec: max(0.01, note.duration)
            )
        }

        sessionNotes.append(contentsOf: recorded)

        let playbackNotes = notes.map { note in
            RecordedNote(
                id: UUID(),
                note: note.note,
                velocity: note.velocity,
                channel: 4,
                startOffsetSec: max(0, note.time),
                durationSec: max(0.01, note.duration)
            )
        }

        let duration = max(0, playbackNotes.map { $0.startOffsetSec + $0.durationSec }.max() ?? 0)
        let take = RecordingTake(
            id: UUID(),
            name: "AI Reply",
            createdAt: playbackStartedAt,
            updatedAt: playbackStartedAt,
            durationSec: duration,
            notes: playbackNotes
        )

        do {
            status = .playing
            try playbackService.play(take: take)
        } catch {
            logger.error("AI playback failed: \(error.localizedDescription, privacy: .public)")
            status = .listening
        }
    }

    private func stopAIPlaybackAndReturnToListening() {
        if playbackService.isPlaying {
            playbackService.stop()
        }
        didFinishAIPlayback()
    }

    private func didFinishAIPlayback() {
        status = .listening
        currentAIPlaybackStartedAt = nil
        saveSessionTake(updatedAt: clock.now())

        if playbackInterruptionBehavior == .queue, !queuedPhrases.isEmpty {
            let next = queuedPhrases.removeFirst()
            startGeneration(for: next)
        }
    }

    private func appendHumanNote(
        note: Int,
        velocity: Int,
        channel: Int,
        startAt: Date,
        endAt: Date
    ) {
        guard let sessionStartedAt else { return }

        let startOffset = max(0, startAt.timeIntervalSince(sessionStartedAt))
        let duration = max(0.01, endAt.timeIntervalSince(startAt))

        sessionNotes.append(
            RecordedNote(
                id: UUID(),
                note: note,
                velocity: velocity,
                channel: channel,
                startOffsetSec: startOffset,
                durationSec: duration
            )
        )

        guard let phraseStartedAt else { return }
        let phraseStartOffset = max(0, startAt.timeIntervalSince(phraseStartedAt))
        phraseNotes.append(
            DialogueNote(
                note: note,
                velocity: velocity,
                time: phraseStartOffset,
                duration: duration
            )
        )
    }

    private func resetPhraseCollection() {
        phraseStartedAt = nil
        phraseNotes.removeAll(keepingCapacity: false)
        openNotes.removeAll(keepingCapacity: false)
    }

    private func saveSessionTake(updatedAt: Date) {
        guard let sessionTakeID,
              let sessionStartedAt,
              let sessionTakeName else { return }

        let notes = sessionNotes.sorted { lhs, rhs in
            if lhs.startOffsetSec != rhs.startOffsetSec {
                return lhs.startOffsetSec < rhs.startOffsetSec
            }
            if lhs.channel != rhs.channel {
                return lhs.channel < rhs.channel
            }
            return lhs.note < rhs.note
        }

        let duration = max(0, notes.map { $0.startOffsetSec + $0.durationSec }.max() ?? 0)

        let take = RecordingTake(
            id: sessionTakeID,
            name: sessionTakeName,
            createdAt: sessionStartedAt,
            updatedAt: updatedAt,
            durationSec: duration,
            notes: notes
        )

        do {
            try recordingRepository.saveTake(take)
            onSessionTakeSaved?(sessionTakeID)
        } catch {
            logger.error("Save dialogue take failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
