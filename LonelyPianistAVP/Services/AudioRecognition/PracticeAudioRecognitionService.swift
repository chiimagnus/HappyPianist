import AVFoundation
import Foundation
import os

final class PracticeAudioRecognitionService: PracticeAudioRecognitionServiceProtocol {
    private enum ServiceError: LocalizedError {
        case permissionDenied
        case invalidInputFormat
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
                case .permissionDenied:
                    return "Microphone permission denied."
                case .invalidInputFormat:
                    return "Invalid microphone input format."
                case let .engineStartFailed(reason):
                    return reason
            }
        }
    }

    var events: AsyncStream<DetectedNoteEvent> {
        eventsStream
    }

    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> {
        statusStream
    }

    var debugSnapshots: AsyncStream<PracticeAudioRecognitionDebugSnapshot> {
        debugStream
    }

    private let audioEngine: AVAudioEngine
    private let processingQueue = DispatchQueue(label: "com.lonelypianist.audio.recognition.processing", qos: .userInitiated)
    private let lock = NSLock()
    private let recognitionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioRecognition"
    )
    private let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioPerformance"
    )

    private let eventsStream: AsyncStream<DetectedNoteEvent>
    private let statusStream: AsyncStream<PracticeAudioRecognitionStatus>
    private let debugStream: AsyncStream<PracticeAudioRecognitionDebugSnapshot>

    private let eventsContinuation: AsyncStream<DetectedNoteEvent>.Continuation
    private let statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation
    private let debugContinuation: AsyncStream<PracticeAudioRecognitionDebugSnapshot>.Continuation

    private var detector = GoertzelNoteDetector()
    private var expectedMIDINotes: [Int] = []
    private var wrongCandidateMIDINotes: [Int] = []
    private var currentGeneration = 0
    private var suppressUntil: Date?
    private var isTapInstalled = false
    private var recentDetectedNotes: [DetectedNoteEvent] = []

    init(audioEngine: AVAudioEngine = AVAudioEngine()) {
        self.audioEngine = audioEngine

        var eventContinuation: AsyncStream<DetectedNoteEvent>.Continuation?
        eventsStream = AsyncStream { continuation in
            eventContinuation = continuation
        }
        var statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation?
        statusStream = AsyncStream { continuation in
            statusContinuation = continuation
        }
        var debugContinuation: AsyncStream<PracticeAudioRecognitionDebugSnapshot>.Continuation?
        debugStream = AsyncStream { continuation in
            debugContinuation = continuation
        }

        eventsContinuation = eventContinuation!
        self.statusContinuation = statusContinuation!
        self.debugContinuation = debugContinuation!
    }

    func start(expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int) async throws {
        stop()
        statusContinuation.yield(.requestingPermission)
        recognitionLogger.info("step3 audio start requested")
        let granted = await requestMicrophonePermission()
        guard granted else {
            statusContinuation.yield(.permissionDenied)
            recognitionLogger.error("step3 audio permission denied")
            throw ServiceError.permissionDenied
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            statusContinuation.yield(.engineFailed(reason: "invalid input format"))
            recognitionLogger.error("step3 audio invalid input format")
            throw ServiceError.invalidInputFormat
        }

        replaceRecognitionTargets(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongCandidateMIDINotes,
            generation: generation
        )

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.processingQueue.async {
                self.processAudioBuffer(buffer)
            }
        }
        isTapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            statusContinuation.yield(.running)
            recognitionLogger.info("step3 audio engine running generation=\(generation, privacy: .public)")
        } catch {
            stop()
            statusContinuation.yield(.engineFailed(reason: error.localizedDescription))
            recognitionLogger.error("step3 audio engine failed \(error.localizedDescription, privacy: .public)")
            throw ServiceError.engineStartFailed(error.localizedDescription)
        }
    }

    func updateExpectedNotes(_ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int) {
        lock.lock()
        self.expectedMIDINotes = expectedMIDINotes
        self.wrongCandidateMIDINotes = wrongCandidateMIDINotes
        currentGeneration = generation
        lock.unlock()
        recognitionLogger.debug(
            "step3 audio update expected=\(expectedMIDINotes.count, privacy: .public) wrong=\(wrongCandidateMIDINotes.count, privacy: .public) generation=\(generation, privacy: .public)"
        )
    }

    func suppressRecognition(until date: Date, generation: Int) {
        lock.lock()
        guard generation == currentGeneration else {
            lock.unlock()
            return
        }
        suppressUntil = date
        lock.unlock()
        recognitionLogger.debug("step3 audio suppress generation=\(generation, privacy: .public)")
    }

    func stop() {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.stop()
        lock.lock()
        expectedMIDINotes.removeAll()
        wrongCandidateMIDINotes.removeAll()
        suppressUntil = nil
        recentDetectedNotes.removeAll()
        lock.unlock()
        statusContinuation.yield(.stopped)
        recognitionLogger.info("step3 audio stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let samples = monoSamples(from: buffer), samples.isEmpty == false else { return }

        lock.lock()
        let expectedMIDINotes = expectedMIDINotes
        let wrongCandidateMIDINotes = wrongCandidateMIDINotes
        let generation = currentGeneration
        let suppressUntil = suppressUntil
        lock.unlock()

        let sampleRate = buffer.format.sampleRate
        let startedAt = CFAbsoluteTimeGetCurrent()
        let debugLoggingEnabled = UserDefaults.standard.bool(forKey: "practiceAudioRecognitionDebugOverlayEnabled")
        let detections = detector.detect(
            samples: samples,
            sampleRate: sampleRate,
            candidateMIDINotes: expectedMIDINotes + wrongCandidateMIDINotes,
            debugLoggingEnabled: debugLoggingEnabled
        )
        if debugLoggingEnabled {
            performanceLogger.debug(
                "step3 audio process ms=\((CFAbsoluteTimeGetCurrent() - startedAt) * 1_000, privacy: .public) detections=\(detections.count, privacy: .public)"
            )
        }

        let now = Date()
        let inputLevel = rms(samples)
        let suppressing = suppressUntil.map { now < $0 } ?? false

        var emittedNotes: [DetectedNoteEvent] = []
        for detection in detections where detection.confidence >= 0.2 {
            let event = DetectedNoteEvent(
                midiNote: detection.midiNote,
                confidence: detection.confidence,
                onsetScore: detection.onsetScore,
                isOnset: detection.isOnset,
                timestamp: now,
                generation: generation,
                source: .audio
            )
            emittedNotes.append(event)
            if suppressing == false {
                eventsContinuation.yield(event)
            }
        }

        lock.lock()
        recentDetectedNotes.append(contentsOf: emittedNotes)
        if recentDetectedNotes.count > 12 {
            recentDetectedNotes.removeFirst(recentDetectedNotes.count - 12)
        }
        let snapshotNotes = recentDetectedNotes
        lock.unlock()

        debugContinuation.yield(
            PracticeAudioRecognitionDebugSnapshot(
                permissionState: .granted,
                engineState: .running,
                inputLevel: inputLevel,
                expectedMIDINotes: expectedMIDINotes,
                recentDetectedNotes: snapshotNotes,
                matchProgress: makeMatchProgress(detections: detections),
                handGate: false,
                suppress: suppressing,
                generation: generation,
                lastDecisionReason: suppressing ? "suppressed" : "live"
            )
        )
    }

    private func replaceRecognitionTargets(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int
    ) {
        lock.lock()
        self.expectedMIDINotes = expectedMIDINotes
        self.wrongCandidateMIDINotes = wrongCandidateMIDINotes
        currentGeneration = generation
        detector = GoertzelNoteDetector()
        suppressUntil = nil
        recentDetectedNotes.removeAll()
        lock.unlock()
    }

    private func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        var result = Array(repeating: Float.zero, count: frameLength)
        for channel in 0 ..< channelCount {
            let values = UnsafeBufferPointer(start: channelData[channel], count: frameLength)
            for index in 0 ..< frameLength {
                result[index] += values[index] / Float(channelCount)
            }
        }
        return result
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func rms(_ samples: [Float]) -> Double {
        let squared = samples.reduce(0.0) { partialResult, sample in
            partialResult + Double(sample * sample)
        }
        return sqrt(squared / Double(max(samples.count, 1)))
    }

    private func makeMatchProgress(detections: [GoertzelNoteDetection]) -> String {
        detections.prefix(3).map { "\($0.midiNote):\(String(format: "%.2f", $0.confidence))" }.joined(separator: " ")
    }
}
