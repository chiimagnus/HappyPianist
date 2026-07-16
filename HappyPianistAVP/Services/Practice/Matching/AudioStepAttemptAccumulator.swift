import Foundation

enum Step3AudioRecognitionMode: String, CaseIterable {
    case lowLatency
    case stricter
}

struct AudioStepAttemptAccumulatorConfiguration: Equatable {
    var singleNoteThreshold: Double = 0.60
    var handBoostedThreshold: Double = 0.50
    var wrongNoteThreshold: Double = 0.72
    var wrongDominanceRatio: Double = 1.25
    var onsetThreshold: Double = 0.35
    var aggregationWindow: TimeInterval = 0.25
    var eventTTL: TimeInterval = 0.35
    var rearmSilenceWindow: TimeInterval = 0.12
    var wrongNoteGraceWindow: TimeInterval = 0.16

    static func configuration(for mode: Step3AudioRecognitionMode) -> AudioStepAttemptAccumulatorConfiguration {
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

final class AudioStepAttemptAccumulator {
    private(set) var configuration: AudioStepAttemptAccumulatorConfiguration

    private var recentEvents: [DetectedNoteEvent] = []
    private var rearmBlockedSince: [Int: Date] = [:]
    private var currentGeneration: Int = 0
    private var recognitionMode: Step3AudioRecognitionMode = .lowLatency
    private var lastMatchedAt: Date?

    init(configuration: AudioStepAttemptAccumulatorConfiguration = .init()) {
        self.configuration = configuration
    }

    func register(event: DetectedNoteEvent) {
        guard event.generation == currentGeneration else { return }
        if event.isOnset {
            rearmBlockedSince[event.midiNote] = nil
        }
        recentEvents.append(event)
    }

    func setMode(_ mode: Step3AudioRecognitionMode) {
        recognitionMode = mode
        configuration = .configuration(for: mode)
    }

    func evaluate(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: Set<Int>,
        generation: Int,
        at timestamp: Date,
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
        let activeEvents = makeActiveEvents(generation: generation, at: timestamp, threshold: threshold)
        let observed = Set(activeEvents.map(\.midiNote))
        let strongestExpected = activeEvents
            .filter { expectedSet.contains($0.midiNote) }
            .map(\.confidence)
            .max() ?? 0
        let strongestWrong = activeEvents
            .filter { wrongCandidateMIDINotes.contains($0.midiNote) }
            .map(\.confidence)
            .max() ?? 0

        if strongestWrong >= configuration.wrongNoteThreshold,
           strongestWrong >= max(strongestExpected, 0.01) * configuration.wrongDominanceRatio
        {
            if let lastMatchedAt, timestamp.timeIntervalSince(lastMatchedAt) <= configuration.wrongNoteGraceWindow {
                return .insufficientEvidence
            }
            return .wrongNote
        }

        guard expectedSet.isSubset(of: observed) else { return .insufficientEvidence }
        lastMatchedAt = timestamp
        return .matched
    }

    func evaluateHandSeparated(
        expectedRightMIDINotes: [Int],
        expectedLeftMIDINotes: [Int],
        wrongCandidateMIDINotes: Set<Int>,
        generation: Int,
        at timestamp: Date,
        handGateBoost: Bool = false
    ) -> StepAttemptMatchResult {
        if generation != currentGeneration {
            currentGeneration = generation
            resetForNewStep(generation: generation)
        }
        pruneExpiredEvents(now: timestamp)

        let expectedUnion = Set(expectedRightMIDINotes + expectedLeftMIDINotes)
        guard expectedUnion.isEmpty == false else { return .insufficientEvidence }

        let threshold = threshold(for: handGateBoost)
        let activeEvents = makeActiveEvents(generation: generation, at: timestamp, threshold: threshold)
        let observed = Set(activeEvents.map(\.midiNote))
        let strongestExpected = activeEvents
            .filter { expectedUnion.contains($0.midiNote) }
            .map(\.confidence)
            .max() ?? 0
        let strongestWrong = activeEvents
            .filter { wrongCandidateMIDINotes.contains($0.midiNote) }
            .map(\.confidence)
            .max() ?? 0

        if strongestWrong >= configuration.wrongNoteThreshold,
           strongestWrong >= max(strongestExpected, 0.01) * configuration.wrongDominanceRatio
        {
            if let lastMatchedAt, timestamp.timeIntervalSince(lastMatchedAt) <= configuration.wrongNoteGraceWindow {
                return .insufficientEvidence
            }
            return .wrongNote
        }

        guard expectedUnion.isSubset(of: observed) else { return .insufficientEvidence }
        lastMatchedAt = timestamp
        return .matched
    }

    func resetForNewStep(generation: Int) {
        currentGeneration = generation
        recentEvents.removeAll()
        lastMatchedAt = nil
    }

    func markMatchedAndRequireRearm(expectedMIDINotes: [Int], at timestamp: Date) {
        for midiNote in Set(expectedMIDINotes) {
            rearmBlockedSince[midiNote] = timestamp
        }
    }

    private func pruneExpiredEvents(now: Date) {
        recentEvents.removeAll { event in
            now.timeIntervalSince(event.timestamp) > configuration.eventTTL
        }
        rearmBlockedSince = rearmBlockedSince.filter { _, blockedAt in
            now.timeIntervalSince(blockedAt) < configuration.rearmSilenceWindow
        }
    }

    private func isEventQualified(_ event: DetectedNoteEvent, threshold: Double) -> Bool {
        event.confidence >= threshold && (event.isOnset || event.onsetScore >= configuration.onsetThreshold)
    }

    private func threshold(for handGateBoost: Bool) -> Double {
        handGateBoost ? configuration.handBoostedThreshold : configuration.singleNoteThreshold
    }

    private func makeActiveEvents(generation: Int, at timestamp: Date, threshold: Double) -> [DetectedNoteEvent] {
        recentEvents.filter { event in
            event.timestamp <= timestamp &&
                timestamp.timeIntervalSince(event.timestamp) <= configuration.aggregationWindow &&
                event.generation == generation &&
                isEventQualified(event, threshold: threshold) &&
                isRearmSatisfied(for: event.midiNote, at: timestamp)
        }
    }

    private func isRearmSatisfied(for midiNote: Int, at timestamp: Date) -> Bool {
        guard let blockedAt = rearmBlockedSince[midiNote] else { return true }
        return timestamp.timeIntervalSince(blockedAt) >= configuration.rearmSilenceWindow
    }
}
