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
                    "Microphone permission denied."
                case .invalidInputFormat:
                    "Invalid microphone input format."
                case let .engineStartFailed(reason):
                    reason
            }
        }
    }

    var events: AsyncStream<DetectedNoteEvent> { eventsStream }
    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> { statusStream }
    var debugSnapshots: AsyncStream<PracticeAudioRecognitionDebugSnapshot> { debugStream }

    private let audioEngine: AVAudioEngine
    private let spectrumAnalyzer: any AudioSpectrumAnalyzing
    private let harmonicDetector: any HarmonicTemplateDetecting
    private let processingQueue = DispatchQueue(label: "com.lonelypianist.audio.recognition.processing", qos: .userInitiated)
    private let lock = NSLock()
    private let detectorLock = NSLock()
    private let recognitionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP", category: "Step3AudioRecognition")
    private let performanceLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP", category: "Step3AudioPerformance")

    private let eventsStream: AsyncStream<DetectedNoteEvent>
    private let statusStream: AsyncStream<PracticeAudioRecognitionStatus>
    private let debugStream: AsyncStream<PracticeAudioRecognitionDebugSnapshot>
    private let eventsContinuation: AsyncStream<DetectedNoteEvent>.Continuation
    private let statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation
    private let debugContinuation: AsyncStream<PracticeAudioRecognitionDebugSnapshot>.Continuation

    private var goertzelDetector = GoertzelNoteDetector()
    private var rollingBuffer = AudioSampleRollingBuffer(capacity: 4096)
    private var requestedDetectorMode: PracticeAudioRecognitionDetectorMode = .automatic
    private var activeDetectorMode: PracticeAudioRecognitionDetectorMode = .harmonicTemplate
    private var tuningProfile: HarmonicTemplateTuningProfile = .lowLatencyDefault
    private var consecutiveSlowFrames = 0
    private var consecutiveDetectorErrors = 0
    private var lastFallbackReason: String?
    private var expectedMIDINotes: [Int] = []
    private var wrongCandidateMIDINotes: [Int] = []
    private var currentGeneration = 0
    private var suppressUntil: Date?
    private var isTapInstalled = false
    private var recentDetectedNotes: [DetectedNoteEvent] = []

    init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        spectrumAnalyzer: any AudioSpectrumAnalyzing = VDSPAudioSpectrumAnalyzer(),
        harmonicDetector: any HarmonicTemplateDetecting = TargetedHarmonicTemplateDetector()
    ) {
        self.audioEngine = audioEngine
        self.spectrumAnalyzer = spectrumAnalyzer
        self.harmonicDetector = harmonicDetector
        var eventContinuation: AsyncStream<DetectedNoteEvent>.Continuation?
        eventsStream = AsyncStream { eventContinuation = $0 }
        var statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation?
        statusStream = AsyncStream { statusContinuation = $0 }
        var debugContinuation: AsyncStream<PracticeAudioRecognitionDebugSnapshot>.Continuation?
        debugStream = AsyncStream { debugContinuation = $0 }
        eventsContinuation = eventContinuation!
        self.statusContinuation = statusContinuation!
        self.debugContinuation = debugContinuation!
    }

    func configureDetectorMode(_ mode: PracticeAudioRecognitionDetectorMode, profile: HarmonicTemplateTuningProfile) {
        lock.lock()
        requestedDetectorMode = mode
        tuningProfile = profile
        activeDetectorMode = mode == .automatic ? .harmonicTemplate : mode
        consecutiveSlowFrames = 0
        consecutiveDetectorErrors = 0
        lastFallbackReason = nil
        rollingBuffer.reset()
        lock.unlock()
    }

    func start(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressUntil: Date?
    ) async throws {
        stop()
        statusContinuation.yield(.requestingPermission)
        let granted = await requestMicrophonePermission()
        guard granted else {
            statusContinuation.yield(.permissionDenied)
            throw ServiceError.permissionDenied
        }
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            statusContinuation.yield(.engineFailed(reason: "invalid input format"))
            throw ServiceError.invalidInputFormat
        }
        replaceRecognitionTargets(expectedMIDINotes: expectedMIDINotes, wrongCandidateMIDINotes: wrongCandidateMIDINotes, generation: generation, suppressUntil: suppressUntil)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let samples = Self.monoSamples(from: buffer), samples.isEmpty == false else { return }
            let sampleRate = buffer.format.sampleRate
            processingQueue.async {
                self.processAudioSamples(samples, sampleRate: sampleRate)
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
            throw ServiceError.engineStartFailed(error.localizedDescription)
        }
    }

    func updateExpectedNotes(_ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int) {
        lock.lock()
        self.expectedMIDINotes = expectedMIDINotes
        self.wrongCandidateMIDINotes = wrongCandidateMIDINotes
        currentGeneration = generation
        recentDetectedNotes.removeAll()
        rollingBuffer.reset()
        detectorLock.lock()
        goertzelDetector = GoertzelNoteDetector()
        detectorLock.unlock()
        lock.unlock()
    }

    func suppressRecognition(until date: Date, generation: Int) {
        lock.lock()
        guard generation == currentGeneration else { lock.unlock(); return }
        suppressUntil = date
        lock.unlock()
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
        rollingBuffer.reset()
        lock.unlock()
        statusContinuation.yield(.stopped)
    }

    private func processAudioSamples(_ samples: [Float], sampleRate: Double) {
        guard samples.isEmpty == false, sampleRate > 0 else { return }
        lock.lock()
        let expectedMIDINotes = expectedMIDINotes
        let wrongCandidateMIDINotes = wrongCandidateMIDINotes
        let generation = currentGeneration
        let suppressUntil = suppressUntil
        let requestedMode = requestedDetectorMode
        let mode = activeDetectorMode
        let profile = tuningProfile
        let fallbackReason = lastFallbackReason
        let preferredWindowSize = profile.preferredWindowSize(for: expectedMIDINotes)
        rollingBuffer.setCapacity(max(preferredWindowSize, profile.lowRegisterWindowSize))
        rollingBuffer.append(samples)
        let analysisWindow = rollingBuffer.window(size: preferredWindowSize)
        lock.unlock()
        guard let analysisWindow else { return }

        let now = Date()
        let suppressing = suppressUntil.map { now < $0 } ?? false
        let startedAt = Date().timeIntervalSinceReferenceDate
        let frame: TargetedHarmonicDetectionFrame
        switch mode {
            case .simpleGoertzel:
                frame = processGoertzelFrame(samples: analysisWindow, sampleRate: sampleRate, expectedMIDINotes: expectedMIDINotes, wrongCandidateMIDINotes: wrongCandidateMIDINotes, generation: generation, suppressing: suppressing, requestedMode: requestedMode, fallbackReason: fallbackReason, startedAt: startedAt)
            case .harmonicTemplate, .automatic:
                frame = processHarmonicFrame(samples: analysisWindow, sampleRate: sampleRate, expectedMIDINotes: expectedMIDINotes, wrongCandidateMIDINotes: wrongCandidateMIDINotes, generation: generation, suppressing: suppressing, requestedMode: requestedMode, profile: profile, startedAt: startedAt)
        }
        publish(frame: frame, inputLevel: rms(analysisWindow), expectedMIDINotes: expectedMIDINotes, generation: generation, suppressing: suppressing)
    }

    private func processHarmonicFrame(
        samples: [Float],
        sampleRate: Double,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        requestedMode: PracticeAudioRecognitionDetectorMode,
        profile: HarmonicTemplateTuningProfile,
        startedAt: TimeInterval
    ) -> TargetedHarmonicDetectionFrame {
        do {
            let spectrum = try spectrumAnalyzer.analyze(samples: samples, sampleRate: sampleRate, timestamp: Date())
            var frame = harmonicDetector.detect(
                spectrumFrame: spectrum,
                expectedMIDINotes: expectedMIDINotes,
                wrongCandidateMIDINotes: wrongCandidateMIDINotes,
                generation: generation,
                suppressing: suppressing,
                requestedMode: requestedMode,
                profile: profile
            )
            let elapsed = ((Date().timeIntervalSinceReferenceDate) - startedAt) * 1000
            updateFallbackCounters(elapsedMs: elapsed, error: nil, profile: profile)
            if elapsed > profile.slowProcessingThresholdMs {
                performanceLogger.debug("harmonic detector slow ms=\(elapsed, privacy: .public)")
            }
            frame = TargetedHarmonicDetectionFrame(events: frame.events, templateMatchResults: frame.templateMatchResults, processingDurationMs: elapsed, suppressing: suppressing, fallbackReason: lastFallbackReason, activeDetectorMode: .harmonicTemplate, rollingWindowSize: spectrum.windowSize)
            return frame
        } catch {
            updateFallbackCounters(elapsedMs: 0, error: error, profile: profile)
            return processGoertzelFrame(samples: samples, sampleRate: sampleRate, expectedMIDINotes: expectedMIDINotes, wrongCandidateMIDINotes: wrongCandidateMIDINotes, generation: generation, suppressing: suppressing, requestedMode: requestedMode, fallbackReason: lastFallbackReason ?? error.localizedDescription, startedAt: startedAt)
        }
    }

    private func processGoertzelFrame(
        samples: [Float],
        sampleRate: Double,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        requestedMode: PracticeAudioRecognitionDetectorMode,
        fallbackReason: String?,
        startedAt: TimeInterval
    ) -> TargetedHarmonicDetectionFrame {
        detectorLock.lock()
        let detections = goertzelDetector.detect(samples: samples, sampleRate: sampleRate, candidateMIDINotes: expectedMIDINotes + wrongCandidateMIDINotes, debugLoggingEnabled: false)
        detectorLock.unlock()
        let events = suppressing ? [] : detections.filter { $0.confidence >= 0.2 }.map { detection in
            DetectedNoteEvent(midiNote: detection.midiNote, confidence: detection.confidence, onsetScore: detection.onsetScore, isOnset: detection.isOnset, timestamp: Date(), generation: generation, source: .audio)
        }
        let matches = detections.map { detection in
            TemplateMatchResult(midiNote: detection.midiNote, role: expectedMIDINotes.contains(detection.midiNote) ? .expected : .wrongCandidate, confidence: detection.confidence, harmonicScore: detection.rawEnergy, tonalRatio: detection.confidence, dominanceOverWrong: 1, strongestPartials: [])
        }
        return TargetedHarmonicDetectionFrame(events: events, templateMatchResults: matches, processingDurationMs: ((Date().timeIntervalSinceReferenceDate) - startedAt) * 1000, suppressing: suppressing, fallbackReason: fallbackReason, activeDetectorMode: .simpleGoertzel, rollingWindowSize: samples.count)
    }

    private func updateFallbackCounters(elapsedMs: Double, error: Error?, profile: HarmonicTemplateTuningProfile) {
        lock.lock()
        if error != nil {
            consecutiveDetectorErrors += 1
        } else {
            consecutiveDetectorErrors = 0
            if elapsedMs > profile.slowProcessingThresholdMs {
                consecutiveSlowFrames += 1
            } else {
                consecutiveSlowFrames = 0
            }
        }
        if requestedDetectorMode == .automatic,
           (consecutiveSlowFrames >= profile.slowFallbackCount || consecutiveDetectorErrors >= profile.errorFallbackCount)
        {
            activeDetectorMode = .simpleGoertzel
            lastFallbackReason = consecutiveDetectorErrors >= profile.errorFallbackCount ? "harmonicTemplate repeated errors" : "harmonicTemplate repeated slow frames"
        }
        lock.unlock()
    }

    private func publish(frame: TargetedHarmonicDetectionFrame, inputLevel: Double, expectedMIDINotes: [Int], generation: Int, suppressing: Bool) {
        for event in frame.events {
            eventsContinuation.yield(event)
        }
        lock.lock()
        recentDetectedNotes.append(contentsOf: frame.events)
        if recentDetectedNotes.count > 12 { recentDetectedNotes.removeFirst(recentDetectedNotes.count - 12) }
        let snapshotNotes = recentDetectedNotes
        let snapshotRequestedDetectorMode = requestedDetectorMode
        lock.unlock()
        debugContinuation.yield(
            PracticeAudioRecognitionDebugSnapshot(
                permissionState: .granted,
                engineState: .running,
                inputLevel: inputLevel,
                expectedMIDINotes: expectedMIDINotes,
                recentDetectedNotes: snapshotNotes,
                matchProgress: makeMatchProgress(results: frame.templateMatchResults),
                handGate: false,
                suppress: suppressing,
                generation: generation,
                lastDecisionReason: frame.fallbackReason ?? (suppressing ? "suppressed" : "live"),
                requestedDetectorMode: snapshotRequestedDetectorMode,
                activeDetectorMode: frame.activeDetectorMode,
                fallbackReason: frame.fallbackReason,
                rollingWindowSize: frame.rollingWindowSize,
                processingDurationMs: frame.processingDurationMs,
                templateMatchResults: frame.templateMatchResults
            )
        )
    }

    private func replaceRecognitionTargets(expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int, suppressUntil: Date?) {
        lock.lock()
        self.expectedMIDINotes = expectedMIDINotes
        self.wrongCandidateMIDINotes = wrongCandidateMIDINotes
        currentGeneration = generation
        self.suppressUntil = suppressUntil
        recentDetectedNotes.removeAll()
        rollingBuffer.reset()
        activeDetectorMode = requestedDetectorMode == .automatic ? .harmonicTemplate : requestedDetectorMode
        consecutiveSlowFrames = 0
        consecutiveDetectorErrors = 0
        lastFallbackReason = nil
        detectorLock.lock()
        goertzelDetector = GoertzelNoteDetector()
        detectorLock.unlock()
        lock.unlock()
    }

    private static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return [] }
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return nil }
        if channelCount == 1 { return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength)) }
        var result = Array(repeating: Float.zero, count: frameLength)
        for channel in 0 ..< channelCount {
            let values = UnsafeBufferPointer(start: channelData[channel], count: frameLength)
            for index in 0 ..< frameLength { result[index] += values[index] / Float(channelCount) }
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
        sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(samples.count, 1)))
    }

    private func makeMatchProgress(results: [TemplateMatchResult]) -> String {
        results.prefix(3).map { "\($0.midiNote):\(String(format: "%.2f", $0.confidence))" }.joined(separator: " ")
    }
}
