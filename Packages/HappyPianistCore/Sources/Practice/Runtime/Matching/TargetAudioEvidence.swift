import Foundation

public struct TargetAudioEvidence: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case detected
        case contradicted
        case mixed
        case unknown
    }

    public let targetMIDINotes: [Int]
    public let targetConfidenceByMIDINote: [Int: Double]
    public let wrongConfidenceByMIDINote: [Int: Double]
    public let confidence: Double?
    public let onsetScore: Double
    public let isOnset: Bool
    public let timestamp: PerformanceMonotonicInstant
    public let generation: Int

    public init(
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
        let strongestConfidence: Double? = if let confidence {
            confidence
        } else {
            Self.strongest(targetConfidence: targetConfidence, wrongConfidence: wrongConfidence)
        }
        self.confidence = strongestConfidence.map { min(1, max(0, $0)) }
        self.onsetScore = min(1, max(0, onsetScore))
        self.isOnset = isOnset
        self.timestamp = timestamp
        self.generation = generation
    }

    public var result: Result {
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
