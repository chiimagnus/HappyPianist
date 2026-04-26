import Foundation
import os

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
    private static let decisionLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioDecision"
    )
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
        Self.decisionLogger.debug("accumulator mode changed to \(mode.rawValue, privacy: .public)")
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
        guard expectedSet.isEmpty == false else {
            return .insufficient(progress: "no expected notes")
        }

        let threshold = handGateBoost ? configuration.handBoostedThreshold : configuration.singleNoteThreshold
        let activeEvents = recentEvents.filter { event in
            event.timestamp <= timestamp &&
                timestamp.timeIntervalSince(event.timestamp) <= configuration.aggregationWindow &&
                event.generation == generation &&
                isEventQualified(event, threshold: threshold) &&
                isRearmSatisfied(for: event.midiNote, at: timestamp)
        }

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
                Self.decisionLogger.debug("audio wrong in grace window generation=\(generation, privacy: .public)")
                return .insufficient(progress: "wrong note grace")
            }
            Self.decisionLogger.debug("audio wrong generation=\(generation, privacy: .public)")
            return .wrong(reason: "wrong note dominates window")
        }

        if expectedSet.count == 1 {
            if strongestExpected >= threshold {
                lastMatchedAt = timestamp
                Self.decisionLogger.debug("audio single matched generation=\(generation, privacy: .public)")
                return .matched(reason: "single note matched")
            }
            return .insufficient(progress: "single note pending")
        }

        let matchedExpectedCount = Set(
            activeEvents
                .filter { expectedSet.contains($0.midiNote) }
                .map(\.midiNote)
        ).count
        let requiredMatches = requiredMatchCount(expectedCount: expectedSet.count)
        if matchedExpectedCount >= requiredMatches {
            lastMatchedAt = timestamp
            Self.decisionLogger.debug("audio chord matched generation=\(generation, privacy: .public)")
            return .matched(reason: "chord majority matched")
        }
        return .insufficient(progress: "chord \(matchedExpectedCount)/\(requiredMatches)")
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

    private func isRearmSatisfied(for midiNote: Int, at timestamp: Date) -> Bool {
        guard let blockedAt = rearmBlockedSince[midiNote] else { return true }
        return timestamp.timeIntervalSince(blockedAt) >= configuration.rearmSilenceWindow
    }

    private func requiredMatchCount(expectedCount: Int) -> Int {
        switch expectedCount {
            case ...0:
                0
            case 1:
                1
            case 2:
                2
            default:
                Int(ceil(Double(expectedCount) * 2.0 / 3.0))
        }
    }
}
