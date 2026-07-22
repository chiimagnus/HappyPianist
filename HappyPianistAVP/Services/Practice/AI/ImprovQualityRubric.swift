import Foundation

/// Response-only quality gate shared by every creative-duet backend.
/// It deliberately does not grade the player's performance or invent harmonic evidence.
struct ImprovQualityRubric {
    enum Dimension: String, CaseIterable, Equatable {
        case density
        case repetition
        case register
        case rhythmicCoherence
        case voiceLeading
        case harmonicFit
        case cadence
        case conflict
        case responseLatency
    }

    enum Evidence: String, Equatable {
        case pass
        case warning
        case fail
        case notObserved
    }

    enum Reason: String, Equatable {
        case densityOverload
        case excessiveRepetition
        case excessiveMotivicRepetition
        case outOfPianoRegister
        case rhythmFragmentation
        case extremeVoiceLeap
        case voiceCrossing
        case harmonicMismatch
        case missingCadence
        case internalNoteConflict
        case responseLatency
    }

    enum Band: String, Equatable {
        case acceptable
        case risky
        case reject
    }

    struct Thresholds: Equatable {
        let version: String
        let riskyDensityPerSecond: Double
        let maximumDensityPerSecond: Double
        let riskyRepeatedRunLength: Int
        let maximumRepeatedRunLength: Int
        let minimumRhythmicGapSeconds: TimeInterval
        let riskyVoiceLeapSemitones: Int
        let maximumVoiceLeapSemitones: Int
        let riskyResponseLatencySeconds: TimeInterval
        let maximumResponseLatencySeconds: TimeInterval
        let riskyMotifRepeatCount: Int
        let maximumMotifRepeatCount: Int

        static let v2 = Self(
            version: "improv-quality-v2",
            riskyDensityPerSecond: 6,
            maximumDensityPerSecond: 10,
            riskyRepeatedRunLength: 3,
            maximumRepeatedRunLength: 7,
            minimumRhythmicGapSeconds: 0.055,
            riskyVoiceLeapSemitones: 16,
            maximumVoiceLeapSemitones: 24,
            riskyResponseLatencySeconds: 0.18,
            maximumResponseLatencySeconds: 0.35,
            riskyMotifRepeatCount: 4,
            maximumMotifRepeatCount: 5
        )
    }

    struct VoicePair: Equatable {
        let bass: Int
        let melody: Int
    }

    struct PhraseContext: Equatable {
        let allowedPitchClasses: Set<Int>?
        let cadencePitchClasses: Set<Int>?
        let finalMelodyPitch: Int?
        let voicePairs: [VoicePair]

        init(
            allowedPitchClasses: Set<Int>? = nil,
            cadencePitchClasses: Set<Int>? = nil,
            finalMelodyPitch: Int? = nil,
            voicePairs: [VoicePair] = []
        ) {
            self.allowedPitchClasses = allowedPitchClasses
            self.cadencePitchClasses = cadencePitchClasses
            self.finalMelodyPitch = finalMelodyPitch
            self.voicePairs = voicePairs
        }
    }

    struct Fixture {
        let response: [PracticeSequencerMIDIEvent]
        let responseLatencySeconds: TimeInterval
    }

    struct Assessment: Equatable {
        let thresholdVersion: String
        let band: Band
        let score: Int
        let reasons: [Reason]
        let dimensions: [Dimension: Evidence]

        var isUsable: Bool {
            band != .reject
        }
    }

    static let defaultFixture = Fixture(
        response: [
            PracticeSequencerMIDIEvent(timeSeconds: 0.05, kind: .noteOn(midi: 64, velocity: 88)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.25, kind: .noteOff(midi: 64)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.30, kind: .noteOn(midi: 67, velocity: 84)),
            PracticeSequencerMIDIEvent(timeSeconds: 0.52, kind: .noteOff(midi: 67)),
        ],
        responseLatencySeconds: 0.12
    )

    private let thresholds: Thresholds

    init(thresholds: Thresholds = .v2) {
        self.thresholds = thresholds
    }

    func assess(
        _ response: [PracticeSequencerMIDIEvent],
        responseLatencySeconds: TimeInterval? = nil,
        context: PhraseContext? = nil
    ) -> Assessment {
        let noteOns = response.compactMap { event -> (time: TimeInterval, midi: Int)? in
            guard case let .noteOn(midi, _) = event.kind else { return nil }
            return (event.timeSeconds, midi)
        }.sorted(by: noteOrder)
        var dimensions = Dictionary(uniqueKeysWithValues: Dimension.allCases.map { ($0, Evidence.notObserved) })
        var reasons: [Reason] = []

        assessDensity(noteOns, response: response, dimensions: &dimensions, reasons: &reasons)
        assessRepetition(noteOns, dimensions: &dimensions, reasons: &reasons)
        assessMotivicRepetition(noteOns, dimensions: &dimensions, reasons: &reasons)
        assessRegister(noteOns, dimensions: &dimensions, reasons: &reasons)
        assessRhythm(noteOns, dimensions: &dimensions, reasons: &reasons)
        assessVoiceLeading(noteOns, dimensions: &dimensions, reasons: &reasons)
        assessVoiceCrossing(context, dimensions: &dimensions, reasons: &reasons)
        assessHarmonicFit(noteOns, context: context, dimensions: &dimensions, reasons: &reasons)
        assessCadence(noteOns, context: context, dimensions: &dimensions, reasons: &reasons)
        assessConflicts(response, noteOns: noteOns, dimensions: &dimensions, reasons: &reasons)
        assessLatency(responseLatencySeconds, dimensions: &dimensions, reasons: &reasons)

        let score = dimensions.values.reduce(100) { score, evidence in
            switch evidence {
            case .fail:
                score - 45
            case .warning:
                score - 15
            case .pass, .notObserved:
                score
            }
        }
        let band: Band = if dimensions.values.contains(.fail) {
            .reject
        } else if dimensions.values.contains(.warning) {
            .risky
        } else {
            .acceptable
        }

        return Assessment(
            thresholdVersion: thresholds.version,
            band: band,
            score: max(0, score),
            reasons: reasons,
            dimensions: dimensions
        )
    }

    private func assessDensity(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        response: [PracticeSequencerMIDIEvent],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard let first = noteOns.first?.time else { return }
        let last = response.map(\.timeSeconds).max() ?? first
        let duration = max(0.35, last - first)
        let density = Double(noteOns.count) / duration
        if density >= thresholds.maximumDensityPerSecond {
            dimensions[.density] = .fail
            reasons.append(.densityOverload)
        } else if density >= thresholds.riskyDensityPerSecond {
            dimensions[.density] = .warning
            reasons.append(.densityOverload)
        } else {
            dimensions[.density] = .pass
        }
    }

    private func assessRepetition(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard let first = noteOns.first else { return }
        var longestRun = 1
        var currentRun = 1
        var previous = first.midi
        for event in noteOns.dropFirst() {
            if event.midi == previous {
                currentRun += 1
            } else {
                longestRun = max(longestRun, currentRun)
                currentRun = 1
                previous = event.midi
            }
        }
        longestRun = max(longestRun, currentRun)

        if longestRun >= thresholds.maximumRepeatedRunLength {
            dimensions[.repetition] = .fail
            reasons.append(.excessiveRepetition)
        } else if longestRun >= thresholds.riskyRepeatedRunLength {
            dimensions[.repetition] = .warning
            reasons.append(.excessiveRepetition)
        } else {
            dimensions[.repetition] = .pass
        }
    }

    private func assessMotivicRepetition(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        let melody = onsetMelody(noteOns)
        guard melody.count >= 9 else { return }
        let intervals = zip(melody.dropFirst(), melody).map { $0 - $1 }
        guard intervals.count >= 8 else { return }

        var longestRepeat = 1
        var currentRepeat = 1
        for index in stride(from: 2, through: intervals.count - 2, by: 2) {
            if intervals[index - 2] == intervals[index], intervals[index - 1] == intervals[index + 1] {
                currentRepeat += 1
            } else {
                longestRepeat = max(longestRepeat, currentRepeat)
                currentRepeat = 1
            }
        }
        longestRepeat = max(longestRepeat, currentRepeat)

        if longestRepeat >= thresholds.maximumMotifRepeatCount {
            dimensions[.repetition] = .fail
            reasons.append(.excessiveMotivicRepetition)
        } else if longestRepeat >= thresholds.riskyMotifRepeatCount,
                  dimensions[.repetition] != .fail
        {
            dimensions[.repetition] = .warning
            reasons.append(.excessiveMotivicRepetition)
        }
    }

    private func assessRegister(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard noteOns.isEmpty == false else { return }
        if noteOns.contains(where: { (21 ... 108).contains($0.midi) == false }) {
            dimensions[.register] = .fail
            reasons.append(.outOfPianoRegister)
        } else {
            dimensions[.register] = .pass
        }
    }

    private func assessRhythm(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        let onsets = Array(Set(noteOns.map(\.time))).sorted()
        guard onsets.count >= 3 else { return }
        let tooShortGaps = zip(onsets.dropFirst(), onsets).count {
            $0 - $1 < thresholds.minimumRhythmicGapSeconds
        }
        if tooShortGaps >= 2 {
            dimensions[.rhythmicCoherence] = .fail
            reasons.append(.rhythmFragmentation)
        } else if tooShortGaps == 1 {
            dimensions[.rhythmicCoherence] = .warning
            reasons.append(.rhythmFragmentation)
        } else {
            dimensions[.rhythmicCoherence] = .pass
        }
    }

    private func assessVoiceLeading(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        let centers = onsetCenters(noteOns)
        guard centers.count >= 2 else { return }
        let maximumLeap = zip(centers.dropFirst(), centers)
            .map { Int(abs($0 - $1).rounded()) }
            .max() ?? 0
        if maximumLeap >= thresholds.maximumVoiceLeapSemitones {
            dimensions[.voiceLeading] = .fail
            reasons.append(.extremeVoiceLeap)
        } else if maximumLeap >= thresholds.riskyVoiceLeapSemitones {
            dimensions[.voiceLeading] = .warning
            reasons.append(.extremeVoiceLeap)
        } else {
            dimensions[.voiceLeading] = .pass
        }
    }

    private func assessVoiceCrossing(
        _ context: PhraseContext?,
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard let context, context.voicePairs.isEmpty == false else { return }
        if context.voicePairs.contains(where: { $0.bass >= $0.melody }) {
            dimensions[.voiceLeading] = .fail
            reasons.append(.voiceCrossing)
        } else if dimensions[.voiceLeading] == .notObserved {
            dimensions[.voiceLeading] = .pass
        }
    }

    private func assessHarmonicFit(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        context: PhraseContext?,
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard let allowedPitchClasses = context?.allowedPitchClasses,
              allowedPitchClasses.isEmpty == false,
              noteOns.isEmpty == false
        else { return }
        if noteOns.contains(where: { allowedPitchClasses.contains(pitchClass($0.midi)) == false }) {
            dimensions[.harmonicFit] = .fail
            reasons.append(.harmonicMismatch)
        } else {
            dimensions[.harmonicFit] = .pass
        }
    }

    private func assessCadence(
        _ noteOns: [(time: TimeInterval, midi: Int)],
        context: PhraseContext?,
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard let cadencePitchClasses = context?.cadencePitchClasses,
              cadencePitchClasses.isEmpty == false
        else { return }
        let melody = onsetMelody(noteOns)
        guard let finalPitch = context?.finalMelodyPitch ?? (melody.count >= 2 ? melody.last : nil) else { return }
        if cadencePitchClasses.contains(pitchClass(finalPitch)) {
            dimensions[.cadence] = .pass
        } else {
            dimensions[.cadence] = .fail
            reasons.append(.missingCadence)
        }
    }

    private func assessConflicts(
        _ response: [PracticeSequencerMIDIEvent],
        noteOns: [(time: TimeInterval, midi: Int)],
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard noteOns.isEmpty == false else { return }
        var openDepthByMIDINote: [Int: Int] = [:]
        var hasConflict = false
        for event in ordered(response) {
            switch event.kind {
            case let .noteOn(midi, _):
                hasConflict = hasConflict || (openDepthByMIDINote[midi, default: 0] > 0)
                openDepthByMIDINote[midi, default: 0] += 1
            case let .noteOff(midi):
                guard (openDepthByMIDINote[midi, default: 0] > 0) else {
                    hasConflict = true
                    continue
                }
                openDepthByMIDINote[midi, default: 0] -= 1
            case .controlChange, .pitchBend, .programChange, .channelPressure, .polyPressure:
                continue
            }
        }
        hasConflict = hasConflict || openDepthByMIDINote.values.contains(where: { $0 > 0 })
        if hasConflict {
            dimensions[.conflict] = .fail
            reasons.append(.internalNoteConflict)
        } else {
            dimensions[.conflict] = .pass
        }
    }

    private func assessLatency(
        _ responseLatencySeconds: TimeInterval?,
        dimensions: inout [Dimension: Evidence],
        reasons: inout [Reason]
    ) {
        guard let responseLatencySeconds else { return }
        guard responseLatencySeconds.isFinite, responseLatencySeconds >= 0 else {
            dimensions[.responseLatency] = .fail
            reasons.append(.responseLatency)
            return
        }
        if responseLatencySeconds >= thresholds.maximumResponseLatencySeconds {
            dimensions[.responseLatency] = .fail
            reasons.append(.responseLatency)
        } else if responseLatencySeconds >= thresholds.riskyResponseLatencySeconds {
            dimensions[.responseLatency] = .warning
            reasons.append(.responseLatency)
        } else {
            dimensions[.responseLatency] = .pass
        }
    }

    private func onsetMelody(_ noteOns: [(time: TimeInterval, midi: Int)]) -> [Int] {
        Dictionary(grouping: noteOns, by: \.time)
            .keys
            .sorted()
            .compactMap { time in
                noteOns.filter { $0.time == time }.map(\.midi).max()
            }
    }

    private func onsetCenters(_ noteOns: [(time: TimeInterval, midi: Int)]) -> [Double] {
        let groups = Dictionary(grouping: noteOns, by: \.time)
        return groups.keys.sorted().compactMap { time -> Double? in
            guard let group = groups[time], group.isEmpty == false else { return nil }
            return Double(group.map(\.midi).reduce(0, +)) / Double(group.count)
        }
    }

    private func pitchClass(_ midi: Int) -> Int {
        ((midi % 12) + 12) % 12
    }

    private func ordered(_ events: [PracticeSequencerMIDIEvent]) -> [PracticeSequencerMIDIEvent] {
        events.enumerated().sorted { lhs, rhs in
            if lhs.element.timeSeconds != rhs.element.timeSeconds {
                return lhs.element.timeSeconds < rhs.element.timeSeconds
            }
            if eventPriority(lhs.element.kind) != eventPriority(rhs.element.kind) {
                return eventPriority(lhs.element.kind) < eventPriority(rhs.element.kind)
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func noteOrder(
        _ lhs: (time: TimeInterval, midi: Int),
        _ rhs: (time: TimeInterval, midi: Int)
    ) -> Bool {
        if lhs.time != rhs.time { return lhs.time < rhs.time }
        return lhs.midi < rhs.midi
    }

    private func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
        case .controlChange:
            0
        case .programChange, .pitchBend, .channelPressure, .polyPressure:
            1
        case .noteOff:
            2
        case .noteOn:
            3
        }
    }
}
