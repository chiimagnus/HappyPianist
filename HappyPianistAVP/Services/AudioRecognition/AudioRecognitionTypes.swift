import Foundation

enum PracticeAudioRecognitionStatus: Equatable {
    case idle
    case requestingPermission
    case permissionDenied
    case running
    case engineFailed(reason: String)
    case stopped
}

protocol PracticeAudioRecognitionServiceProtocol: AnyObject {
    var targetEvidence: AsyncStream<TargetAudioEvidence> { get }
    var statusUpdates: AsyncStream<PracticeAudioRecognitionStatus> { get }

    func start(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressUntil: Date?
    ) async throws
    func updateExpectedNotes(
        _ expectedMIDINotes: [Int], wrongCandidateMIDINotes: [Int], generation: Int
    )
    func suppressRecognition(until date: Date, generation: Int)
    func stop()
}

struct TargetAudioEvidence: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case detected
        case contradicted
        case mixed
        case unknown
    }

    let targetMIDINotes: [Int]
    let targetConfidenceByMIDINote: [Int: Double]
    let wrongConfidenceByMIDINote: [Int: Double]
    let confidence: Double?
    let onsetScore: Double
    let isOnset: Bool
    let timestamp: PerformanceMonotonicInstant
    let generation: Int

    init(
        targetMIDINotes: [Int],
        targetConfidenceByMIDINote: [Int: Double],
        wrongConfidenceByMIDINote: [Int: Double],
        confidence: Double? = nil,
        onsetScore: Double,
        isOnset: Bool,
        timestamp: PerformanceMonotonicInstant,
        generation: Int
    ) {
        self.targetMIDINotes = Set(targetMIDINotes).sorted()
        let targetConfidence = Self.clamped(targetConfidenceByMIDINote)
        let wrongConfidence = Self.clamped(wrongConfidenceByMIDINote)
        self.targetConfidenceByMIDINote = targetConfidence
        self.wrongConfidenceByMIDINote = wrongConfidence
        let strongestConfidence: Double?
        if let confidence {
            strongestConfidence = confidence
        } else {
            strongestConfidence = Self.strongest(
                targetConfidence: targetConfidence,
                wrongConfidence: wrongConfidence
            )
        }
        self.confidence = strongestConfidence.map { min(1, max(0, $0)) }
        self.onsetScore = min(1, max(0, onsetScore))
        self.isOnset = isOnset
        self.timestamp = timestamp
        self.generation = generation
    }

    var result: Result {
        switch (targetConfidenceByMIDINote.isEmpty, wrongConfidenceByMIDINote.isEmpty) {
        case (false, false): .mixed
        case (false, true): .detected
        case (true, false): .contradicted
        case (true, true): .unknown
        }
    }

    private static func strongest(
        targetConfidence: [Int: Double],
        wrongConfidence: [Int: Double]
    ) -> Double? {
        let target = targetConfidence.values.max()
        let wrong = wrongConfidence.values.max()
        return switch (target, wrong) {
        case let (target?, wrong?): max(target, wrong)
        case let (target?, nil): target
        case let (nil, wrong?): wrong
        case (nil, nil): nil
        }
    }

    private static func clamped(_ values: [Int: Double]) -> [Int: Double] {
        values.reduce(into: [:]) { output, element in
            output[element.key] = min(1, max(0, element.value))
        }
    }
}

struct TemplateMatchResult: Equatable {
    let midiNote: Int
    let role: HarmonicTemplateCandidateRole
    let confidence: Double
    let tonalRatio: Double
    let dominanceOverWrong: Double
}
