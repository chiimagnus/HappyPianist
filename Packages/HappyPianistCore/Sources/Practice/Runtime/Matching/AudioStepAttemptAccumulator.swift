import Foundation

public enum Step3AudioRecognitionMode: String, CaseIterable, Sendable {
    case lowLatency
    case stricter
}

public struct AudioStepAttemptAccumulatorConfiguration: Equatable, Sendable {
    public var singleNoteThreshold: Double = 0.60
    public var handBoostedThreshold: Double = 0.50
    public var wrongNoteThreshold: Double = 0.72
    public var wrongDominanceRatio: Double = 1.25
    public var onsetThreshold: Double = 0.35
    public var aggregationWindow: TimeInterval = 0.25
    public var eventTTL: TimeInterval = 0.35
    public var rearmSilenceWindow: TimeInterval = 0.12
    public var wrongNoteGraceWindow: TimeInterval = 0.16

    public init(
        singleNoteThreshold: Double = 0.60,
        handBoostedThreshold: Double = 0.50,
        wrongNoteThreshold: Double = 0.72,
        wrongDominanceRatio: Double = 1.25,
        onsetThreshold: Double = 0.35,
        aggregationWindow: TimeInterval = 0.25,
        eventTTL: TimeInterval = 0.35,
        rearmSilenceWindow: TimeInterval = 0.12,
        wrongNoteGraceWindow: TimeInterval = 0.16
    ) {
        self.singleNoteThreshold = singleNoteThreshold
        self.handBoostedThreshold = handBoostedThreshold
        self.wrongNoteThreshold = wrongNoteThreshold
        self.wrongDominanceRatio = wrongDominanceRatio
        self.onsetThreshold = onsetThreshold
        self.aggregationWindow = aggregationWindow
        self.eventTTL = eventTTL
        self.rearmSilenceWindow = rearmSilenceWindow
        self.wrongNoteGraceWindow = wrongNoteGraceWindow
    }

    public static func configuration(for mode: Step3AudioRecognitionMode) -> AudioStepAttemptAccumulatorConfiguration {
        switch mode {
        case .lowLatency:
            AudioStepAttemptAccumulatorConfiguration(
                singleNoteThreshold: 0.55,
                handBoostedThreshold: 0.46,
                wrongNoteThreshold: 0.70,
                wrongDominanceRatio: 1.20,
                onsetThreshold: 0.32,
                aggregationWindow: 0.20,
                eventTTL: 0.30,
                rearmSilenceWindow: 0.10,
                wrongNoteGraceWindow: 0.18
            )
        case .stricter:
            AudioStepAttemptAccumulatorConfiguration(
                singleNoteThreshold: 0.70,
                handBoostedThreshold: 0.62,
                wrongNoteThreshold: 0.72,
                wrongDominanceRatio: 1.40,
                onsetThreshold: 0.40,
                aggregationWindow: 0.28,
                eventTTL: 0.40,
                rearmSilenceWindow: 0.12,
                wrongNoteGraceWindow: 0.18
            )
        }
    }
}

public final class AudioStepAttemptAccumulator {
    public private(set) var configuration: AudioStepAttemptAccumulatorConfiguration

    private var recentEvidence: [TargetAudioEvidence] = []
    private var rearmBlockedSince: [Int: PerformanceMonotonicInstant] = [:]
    private var currentGeneration: Int = 0
    private var recognitionMode: Step3AudioRecognitionMode = .lowLatency
    private var lastMatchedAt: PerformanceMonotonicInstant?

    public init(configuration: AudioStepAttemptAccumulatorConfiguration = .init()) {
        self.configuration = configuration
    }

    public func register(evidence: TargetAudioEvidence) {
        guard evidence.generation == currentGeneration else { return }
        if evidence.isOnset {
            for midiNote in evidence.targetConfidenceByMIDINote.keys {
                rearmBlockedSince[midiNote] = nil
            }
        }
        recentEvidence.append(evidence)
    }

    public func setMode(_ mode: Step3AudioRecognitionMode) {
        recognitionMode = mode
        configuration = .configuration(for: mode)
    }

    public func evaluate(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: Set<Int>,
        generation: Int,
        at timestamp: PerformanceMonotonicInstant,
        handGateBoost: Bool = false
    ) -> StepAttemptMatchResult {
        if generation != currentGeneration {
            currentGeneration = generation
            resetForNewStep(generation: generation)
        }
        pruneExpiredEvents(now: timestamp)

        let expectedSet = Set(expectedMIDINotes)
        guard expectedSet.isEmpty == false else { return .insufficientEvidence }

        let threshold = threshold(for: handGateBoost)
        let activeEvidence = makeActiveEvidence(generation: generation, at: timestamp)
        let targetConfidence = mergedConfidence(activeEvidence, keyPath: \.targetConfidenceByMIDINote)
        let wrongConfidence = mergedConfidence(activeEvidence, keyPath: \.wrongConfidenceByMIDINote)
        let observed = Set(targetConfidence.compactMap { midiNote, confidence in
            confidence >= threshold && isRearmSatisfied(for: midiNote, at: timestamp) ? midiNote : nil
        })
        let strongestExpected = expectedSet.compactMap { targetConfidence[$0] }.max() ?? 0
        let strongestWrong = wrongCandidateMIDINotes.compactMap { wrongConfidence[$0] }.max() ?? 0

        if strongestWrong >= configuration.wrongNoteThreshold,
           strongestWrong >= max(strongestExpected, 0.01) * configuration.wrongDominanceRatio
        {
            if let lastMatchedAt, timestamp.seconds - lastMatchedAt.seconds <= configuration.wrongNoteGraceWindow {
                return .insufficientEvidence
            }
            return .wrongNote
        }

        guard expectedSet.isSubset(of: observed) else { return .insufficientEvidence }
        lastMatchedAt = timestamp
        return .matched
    }

    public func resetForNewStep(generation: Int) {
        currentGeneration = generation
        recentEvidence.removeAll()
        lastMatchedAt = nil
    }

    public func markMatchedAndRequireRearm(
        expectedMIDINotes: [Int],
        at timestamp: PerformanceMonotonicInstant
    ) {
        for midiNote in Set(expectedMIDINotes) {
            rearmBlockedSince[midiNote] = timestamp
        }
    }

    private func pruneExpiredEvents(now: PerformanceMonotonicInstant) {
        recentEvidence.removeAll { evidence in
            now.seconds - evidence.timestamp.seconds > configuration.eventTTL
        }
        rearmBlockedSince = rearmBlockedSince.filter { _, blockedAt in
            now.seconds - blockedAt.seconds < configuration.rearmSilenceWindow
        }
    }

    private func threshold(for handGateBoost: Bool) -> Double {
        handGateBoost ? configuration.handBoostedThreshold : configuration.singleNoteThreshold
    }

    private func makeActiveEvidence(
        generation: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> [TargetAudioEvidence] {
        recentEvidence.filter { evidence in
            evidence.timestamp <= timestamp &&
                timestamp.seconds - evidence.timestamp.seconds <= configuration.aggregationWindow &&
                evidence.generation == generation &&
                (evidence.isOnset || evidence.onsetScore >= configuration.onsetThreshold)
        }
    }

    private func mergedConfidence(
        _ evidence: [TargetAudioEvidence],
        keyPath: KeyPath<TargetAudioEvidence, [Int: Double]>
    ) -> [Int: Double] {
        evidence.reduce(into: [:]) { output, item in
            for (midiNote, confidence) in item[keyPath: keyPath] {
                output[midiNote] = max(output[midiNote] ?? 0, confidence)
            }
        }
    }

    private func isRearmSatisfied(
        for midiNote: Int,
        at timestamp: PerformanceMonotonicInstant
    ) -> Bool {
        guard let blockedAt = rearmBlockedSince[midiNote] else { return true }
        return timestamp.seconds - blockedAt.seconds >= configuration.rearmSilenceWindow
    }
}
