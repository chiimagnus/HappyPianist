import AVFoundation
import Foundation

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

    private struct AudioProcessingRequest {
        let samples: [Float]
        let sampleRate: Double
        let epoch: Int
    }

    private final class ProcessingProxy: @unchecked Sendable {
        private weak var service: PracticeAudioRecognitionService?

        init(service: PracticeAudioRecognitionService) {
            self.service = service
        }

        func process(_ request: AudioProcessingRequest) {
            service?.processAudioSamples(request)
        }
    }

    var targetEvidence: AsyncStream<TargetAudioEvidence> {
        evidenceStream
    }

    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> {
        statusStream
    }

    private let audioEngine: AVAudioEngine
    private let spectrumAnalyzer: any AudioSpectrumAnalyzingProtocol
    private let harmonicDetector: any HarmonicTemplateDetectingProtocol
    private let tuningProfile: HarmonicTemplateTuningProfile
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let lock = NSLock()

    private let evidenceStream: AsyncStream<TargetAudioEvidence>
    private let statusStream: AsyncStream<PracticeAudioRecognitionStatus>
    private let processingStream: AsyncStream<AudioProcessingRequest>
    private let evidenceContinuation: AsyncStream<TargetAudioEvidence>.Continuation
    private let statusContinuation: AsyncStream<PracticeAudioRecognitionStatus>.Continuation
    private let processingContinuation: AsyncStream<AudioProcessingRequest>.Continuation
    private var processingTask: Task<Void, Never>?

    private var rollingBuffer = AudioSampleRollingBuffer(capacity: 4096)
    private var expectedMIDINotes: [Int] = []
    private var wrongCandidateMIDINotes: [Int] = []
    private var currentGeneration = 0
    private var suppressUntil: Date?
    private var isTapInstalled = false
    private var processingEpoch = 0

    init(
        audioEngine: AVAudioEngine = AVAudioEngine(),
        spectrumAnalyzer: any AudioSpectrumAnalyzingProtocol = VDSPAudioSpectrumAnalyzer(),
        harmonicDetector: any HarmonicTemplateDetectingProtocol = TargetedHarmonicTemplateDetector(),
        tuningProfile: HarmonicTemplateTuningProfile = .lowLatencyDefault,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.audioEngine = audioEngine
        self.spectrumAnalyzer = spectrumAnalyzer
        self.harmonicDetector = harmonicDetector
        self.tuningProfile = tuningProfile
        self.diagnosticsReporter = diagnosticsReporter
        (evidenceStream, evidenceContinuation) = AsyncStream.makeStream()
        (statusStream, statusContinuation) = AsyncStream.makeStream()
        (processingStream, processingContinuation) = AsyncStream.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        let proxy = ProcessingProxy(service: self)
        processingTask = Task.detached(priority: .userInitiated) { [processingStream] in
            for await request in processingStream {
                guard Task.isCancelled == false else { return }
                proxy.process(request)
            }
        }
    }

    deinit {
        evidenceContinuation.finish()
        statusContinuation.finish()
        processingContinuation.finish()
        processingTask?.cancel()
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
        try Task.checkCancellation()
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
        replaceRecognitionTargets(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongCandidateMIDINotes,
            generation: generation,
            suppressUntil: suppressUntil
        )
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let samples = Self.monoSamples(from: buffer), samples.isEmpty == false else { return }
            scheduleProcessing(samples: samples, sampleRate: buffer.format.sampleRate)
        }
        isTapInstalled = true
        do {
            audioEngine.prepare()
            try audioEngine.start()
            try Task.checkCancellation()
            statusContinuation.yield(.running)
        } catch is CancellationError {
            stop()
            throw CancellationError()
        } catch {
            stop()
            statusContinuation.yield(.engineFailed(reason: error.localizedDescription))
            throw ServiceError.engineStartFailed(error.localizedDescription)
        }
    }

    func updateExpectedNotes(
        _ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int
    ) {
        lock.lock()
        self.expectedMIDINotes = expectedMIDINotes
        self.wrongCandidateMIDINotes = wrongCandidateMIDINotes
        currentGeneration = generation
        processingEpoch &+= 1
        rollingBuffer.reset()
        lock.unlock()
    }

    func suppressRecognition(until date: Date, generation: Int) {
        lock.lock()
        guard generation == currentGeneration else {
            lock.unlock()
            return
        }
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
        processingEpoch &+= 1
        rollingBuffer.reset()
        lock.unlock()
        statusContinuation.yield(.stopped)
    }

    private func scheduleProcessing(samples: [Float], sampleRate: Double) {
        lock.lock()
        let epoch = processingEpoch
        lock.unlock()
        processingContinuation.yield(
            AudioProcessingRequest(samples: samples, sampleRate: sampleRate, epoch: epoch)
        )
    }

    private func processAudioSamples(_ request: AudioProcessingRequest) {
        guard request.samples.isEmpty == false, request.sampleRate > 0 else { return }
        lock.lock()
        guard request.epoch == processingEpoch else {
            lock.unlock()
            return
        }
        let expectedMIDINotes = expectedMIDINotes
        let wrongCandidateMIDINotes = wrongCandidateMIDINotes
        let generation = currentGeneration
        let suppressUntil = suppressUntil
        let preferredWindowSize = tuningProfile.preferredWindowSize(for: expectedMIDINotes)
        rollingBuffer.setCapacity(max(preferredWindowSize, tuningProfile.lowRegisterWindowSize))
        rollingBuffer.append(request.samples)
        let analysisWindow = rollingBuffer.window(size: preferredWindowSize)
        lock.unlock()
        guard let analysisWindow else { return }

        let now = Date.now
        let suppressing = suppressUntil.map { now < $0 } ?? false
        let evidence = detectEvidence(
            samples: analysisWindow,
            sampleRate: request.sampleRate,
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongCandidateMIDINotes,
            generation: generation,
            suppressing: suppressing
        )
        publish(evidence: evidence, processingEpoch: request.epoch)
    }

    private func detectEvidence(
        samples: [Float],
        sampleRate: Double,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool
    ) -> TargetAudioEvidence? {
        do {
            let spectrum = try spectrumAnalyzer.analyze(
                samples: samples, sampleRate: sampleRate, timestamp: .now
            )
            return harmonicDetector.detect(
                spectrumFrame: spectrum,
                expectedMIDINotes: expectedMIDINotes,
                wrongCandidateMIDINotes: wrongCandidateMIDINotes,
                generation: generation,
                suppressing: suppressing,
                profile: tuningProfile
            )
        } catch {
            diagnosticsReporter?.recordSystem(
                severity: .error,
                category: .audio,
                stage: "harmonicDetector.detect",
                summary: "谐波检测失败",
                reason: error.localizedDescription
            )
            return nil
        }
    }

    private func publish(evidence: TargetAudioEvidence?, processingEpoch: Int) {
        lock.lock()
        let isCurrent = processingEpoch == self.processingEpoch
        lock.unlock()
        guard isCurrent, let evidence else { return }
        evidenceContinuation.yield(evidence)
    }

    private func replaceRecognitionTargets(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressUntil: Date?
    ) {
        lock.lock()
        self.expectedMIDINotes = expectedMIDINotes
        self.wrongCandidateMIDINotes = wrongCandidateMIDINotes
        currentGeneration = generation
        self.suppressUntil = suppressUntil
        processingEpoch &+= 1
        rollingBuffer.reset()
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
}
