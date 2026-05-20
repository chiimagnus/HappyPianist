import Foundation
import ImprovProtocol

public struct DeterministicImprovGenerator: Sendable {
    public init() {}

    public func generateDeterministicResponse(
        notes: [ImprovDialogueNote],
        params: ImprovGenerateParams,
        seed: UInt64?
    ) -> [ImprovDialogueNote] {
        let sourceEvents = notes.map { note in
            NoteEvent(
                note: note.note,
                velocity: note.velocity,
                start: note.time,
                duration: note.duration
            )
        }

        let analysis = analyze(events: sourceEvents)
        let continuationLength = deriveResponseLengthSeconds(params: params)

        let continuation = generateMelodyContinuation(
            sourceNotes: sourceEvents,
            analysis: analysis,
            continuationDuration: continuationLength,
            seed: seed
        )

        let replyNotes = continuation.map { event in
            ImprovDialogueNote(
                note: event.note,
                velocity: event.velocity,
                time: event.start,
                duration: event.duration
            )
        }

        guard let minTime = replyNotes.map(\.time).min(), minTime > 0 else {
            return replyNotes
        }

        return replyNotes.map { note in
            ImprovDialogueNote(
                note: note.note,
                velocity: note.velocity,
                time: max(0.0, note.time - minTime),
                duration: note.duration
            )
        }
    }

    public func deriveResponseLengthSeconds(params: ImprovGenerateParams) -> Double {
        let seconds = Double(params.maxTokens) / 64.0
        return max(2.0, min(seconds, 30.0))
    }

    public func analyzeDialogueNotes(_ notes: [ImprovDialogueNote]) -> MidiAnalysis {
        let events = notes.map { note in
            NoteEvent(
                note: note.note,
                velocity: note.velocity,
                start: note.time,
                duration: note.duration
            )
        }
        return analyze(events: events)
    }

    // MARK: - Core Types

    public struct NoteEvent: Equatable, Sendable {
        public var note: Int
        public var velocity: Int
        public var start: Double
        public var duration: Double

        public init(note: Int, velocity: Int, start: Double, duration: Double) {
            self.note = note
            self.velocity = velocity
            self.start = start
            self.duration = duration
        }
    }

    public struct MidiAnalysis: Sendable {
        public var tempoBPM: Double
        public var timeSignature: (Int, Int)
        public var keySignature: String
        public var keyRoot: Int
        public var keyMode: String
        public var pitchRange: (Int, Int)
        public var averageVelocity: Double
        public var densityNotesPerSecond: Double
        public var durationSeconds: Double
        public var signatureCount: Int
        public var noteCount: Int
        public var motif: [NoteEvent]

        public init(
            tempoBPM: Double,
            timeSignature: (Int, Int),
            keySignature: String,
            keyRoot: Int,
            keyMode: String,
            pitchRange: (Int, Int),
            averageVelocity: Double,
            densityNotesPerSecond: Double,
            durationSeconds: Double,
            signatureCount: Int,
            noteCount: Int,
            motif: [NoteEvent]
        ) {
            self.tempoBPM = tempoBPM
            self.timeSignature = timeSignature
            self.keySignature = keySignature
            self.keyRoot = keyRoot
            self.keyMode = keyMode
            self.pitchRange = pitchRange
            self.averageVelocity = averageVelocity
            self.densityNotesPerSecond = densityNotesPerSecond
            self.durationSeconds = durationSeconds
            self.signatureCount = signatureCount
            self.noteCount = noteCount
            self.motif = motif
        }
    }

    // MARK: - Analysis (ported from midi_generation.py)

    private static let majorScale: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
    private static let minorScale: Set<Int> = [0, 2, 3, 5, 7, 8, 10]

    private static let keySignatureByClass: [Int: String] = [
        0: "C",
        1: "Gb",
        2: "D",
        3: "Eb",
        4: "E",
        5: "F",
        6: "F#",
        7: "G",
        8: "Ab",
        9: "A",
        10: "Bb",
        11: "B",
    ]

    private func tempoToBPM(microsecondsPerBeat: Int) -> Double {
        60_000_000.0 / Double(microsecondsPerBeat)
    }

    private func keySignatureName(rootClass: Int, mode: String) -> String {
        var rootClassAdjusted = rootClass
        if mode == "minor" {
            rootClassAdjusted = (rootClassAdjusted + 3) % 12
        }
        return Self.keySignatureByClass[rootClassAdjusted] ?? "C"
    }

    private func bestKeySignature(notes: [NoteEvent]) -> (String, Int, String) {
        guard notes.isEmpty == false else {
            return ("C", 60, "major")
        }

        var histogram = Array(repeating: 0, count: 12)
        for note in notes {
            histogram[note.note.mod(12)] += 1
        }

        func scoreRoot(_ root: Int, scale: Set<Int>) -> Int {
            scale.reduce(0) { partial, degree in
                partial + histogram[(root + degree).mod(12)]
            }
        }

        var majorBest: (score: Int, root: Int) = (score: Int.min, root: 0)
        var minorBest: (score: Int, root: Int) = (score: Int.min, root: 0)
        for root in 0..<12 {
            let majorScore = scoreRoot(root, scale: Self.majorScale)
            if majorScore > majorBest.score || (majorScore == majorBest.score && root > majorBest.root) {
                majorBest = (majorScore, root)
            }
            let minorScore = scoreRoot(root, scale: Self.minorScale)
            if minorScore > minorBest.score || (minorScore == minorBest.score && root > minorBest.root) {
                minorBest = (minorScore, root)
            }
        }

        if majorBest.score >= minorBest.score {
            let keyName = keySignatureName(rootClass: majorBest.root, mode: "major")
            return (keyName, 60 + majorBest.root, "major")
        }

        let keyName = keySignatureName(rootClass: minorBest.root, mode: "minor")
        return (keyName, 60 + minorBest.root, "minor")
    }

    private func computeAnalysis(
        notes: [NoteEvent],
        keySignature: String,
        keyRoot: Int,
        keyMode: String,
        tempo: Int,
        timeSignature: (Int, Int)
    ) -> MidiAnalysis {
        let durationSeconds = notes.map { $0.start + $0.duration }.max() ?? 0.0

        let pitchMin: Int
        let pitchMax: Int
        let velocityAverage: Double
        if notes.isEmpty == false {
            pitchMin = notes.map(\.note).min() ?? 60
            pitchMax = notes.map(\.note).max() ?? 72
            velocityAverage = notes.map { Double($0.velocity) }.average() ?? 64.0
        } else {
            pitchMin = 60
            pitchMax = 72
            velocityAverage = 64.0
        }

        let density = Double(notes.count) / max(1.0, durationSeconds)
        let (detectedKey, detectedRoot, detectedMode) = bestKeySignature(notes: notes)

        let motif: [NoteEvent]
        if notes.count >= 4 {
            motif = Array(notes.suffix(4))
        } else {
            motif = notes
        }

        return MidiAnalysis(
            tempoBPM: tempoToBPM(microsecondsPerBeat: tempo),
            timeSignature: timeSignature,
            keySignature: detectedKey,
            keyRoot: detectedRoot,
            keyMode: detectedMode,
            pitchRange: (pitchMin, pitchMax),
            averageVelocity: velocityAverage,
            densityNotesPerSecond: density,
            durationSeconds: durationSeconds,
            signatureCount: notes.count,
            noteCount: notes.count,
            motif: motif
        )
    }

    private func analyze(events: [NoteEvent]) -> MidiAnalysis {
        computeAnalysis(
            notes: events.sorted { $0.start < $1.start },
            keySignature: "C",
            keyRoot: 60,
            keyMode: "major",
            tempo: 500_000,
            timeSignature: (4, 4)
        )
    }

    // MARK: - Continuation (ported from midi_generation.py)

    private func scaleNotes(root: Int, mode: String) -> Set<Int> {
        let rootPitch = root.mod(12)
        let degrees = mode == "minor" ? Self.minorScale : Self.majorScale
        return Set(degrees.map { (rootPitch + $0).mod(12) })
    }

    private func closestScaleNote(pitch: Int, scale: Set<Int>, root: Int) -> Int {
        let base = pitch.mod(12)
        if scale.contains(base) {
            return pitch
        }

        let candidates = [-2, -1, 1, 2, -3, 3].map { pitch + $0 }
        let valid = candidates.filter { candidate in
            scale.contains(candidate.mod(12)) && (21...108).contains(candidate)
        }
        return valid.first ?? pitch
    }

    private func extractPhrases(notes: [NoteEvent], minLen: Int = 6, maxLen: Int = 16) -> [[NoteEvent]] {
        if notes.count < minLen {
            return notes.isEmpty ? [] : [notes]
        }

        var phrases: [[NoteEvent]] = []

        for length in [maxLen, maxLen - 4, maxLen - 8] {
            if length >= minLen, notes.count >= length {
                phrases.append(Array(notes.suffix(length)))
            }
        }

        let step = maxLen / 2
        let startMin = max(0, notes.count - maxLen * 4)
        let startMax = notes.count - maxLen
        if startMin < startMax, step > 0 {
            for start in stride(from: startMin, to: startMax, by: step) {
                let end = start + maxLen
                guard end <= notes.count else { continue }
                let phrase = Array(notes[start..<end])
                if phrase.count >= minLen {
                    phrases.append(phrase)
                }
            }
        }

        var unique: [[NoteEvent]] = []
        var seen = Set<[Int]>()
        for phrase in phrases {
            let key = phrase.map(\.note)
            if seen.contains(key) == false {
                seen.insert(key)
                unique.append(phrase)
            }
        }

        if unique.isEmpty {
            return [Array(notes.suffix(minLen))]
        }
        return unique
    }

    private func phraseToDegrees(phrase: [NoteEvent], keyRoot: Int) -> [Int] {
        phrase.map { $0.note - keyRoot }
    }

    private func applyInversion(degrees: [Int]) -> [Int] {
        guard let first = degrees.first else { return degrees }
        var result: [Int] = [first]
        for i in 1..<degrees.count {
            let interval = degrees[i] - degrees[i - 1]
            result.append((result.last ?? 0) - interval)
        }
        return result
    }

    private func applySequence(degrees: [Int], shift: Int) -> [Int] {
        degrees.map { $0 + shift }
    }

    private func applyRhythmicVariation(phrase: [NoteEvent], densityFactor: Double = 1.0) -> [(dur: Double, gap: Double)] {
        var result: [(dur: Double, gap: Double)] = []
        result.reserveCapacity(phrase.count)
        for i in 0..<phrase.count {
            let note = phrase[i]
            let dur = note.duration
            let gap: Double
            if i + 1 < phrase.count {
                gap = phrase[i + 1].start - note.start
            } else {
                gap = note.duration
            }

            var effectiveGap = gap
            var effectiveDur = dur
            if effectiveGap > 0.6, densityFactor > 1.0 {
                effectiveGap /= densityFactor
                effectiveDur /= densityFactor
            }
            result.append((dur: max(0.1, effectiveDur), gap: max(0.1, effectiveGap)))
        }
        return result
    }

    private func quantizeToScale(pitch: Int, scale: Set<Int>, keyRoot: Int) -> Int {
        let pc = pitch.mod(12)
        if scale.contains(pc) {
            return pitch
        }

        for offset in [1, -1, 2, -2, 3, -3, 4, -4] {
            let candidate = pitch + offset
            if scale.contains(candidate.mod(12)), (21...108).contains(candidate) {
                return candidate
            }
        }

        return max(21, min(108, closestScaleNote(pitch: pitch, scale: scale, root: keyRoot)))
    }

    private func clampPitch(pitch: Int, pitchRange: (Int, Int)) -> Int {
        let (lo, hi) = pitchRange
        let margin = 3
        return max(lo - margin, min(hi + margin, pitch))
    }

    private func generateMelodyContinuation(
        sourceNotes: [NoteEvent],
        analysis: MidiAnalysis,
        continuationDuration: Double,
        seed: UInt64?
    ) -> [NoteEvent] {
        guard sourceNotes.isEmpty == false else {
            let tonic = analysis.keyRoot
            return [NoteEvent(note: tonic, velocity: 80, start: 0.0, duration: 0.4)]
        }

        var rng = PythonRandom(seed: seed ?? 0)

        let startTime = sourceNotes.map { $0.start + $0.duration }.max() ?? 0.0
        let scale = scaleNotes(root: analysis.keyRoot, mode: analysis.keyMode)
        let baseVelocity = 95
        let pitchRange = analysis.pitchRange

        var phrases = extractPhrases(notes: sourceNotes)
        if phrases.isEmpty {
            phrases = [Array(sourceNotes.suffix(4))]
        }

        let phraseDegrees = phrases.map { phraseToDegrees(phrase: $0, keyRoot: analysis.keyRoot) }

        let targetGap = min(0.8, max(0.15, 1.0 / max(analysis.densityNotesPerSecond, 0.5)))
        let maxGap = max(1.0, targetGap * 2.0)

        func varyDegrees(degrees: [Int], strategy: String) -> [Int] {
            switch strategy {
            case "inversion":
                return applyInversion(degrees: degrees)
            case "sequence_up":
                let shift = analysis.keyMode == "major" ? 4 : 3
                return applySequence(degrees: degrees, shift: shift)
            case "sequence_down":
                let shift = analysis.keyMode == "major" ? -4 : -3
                return applySequence(degrees: degrees, shift: shift)
            case "retrograde":
                return degrees.reversed()
            case "ornament":
                if degrees.isEmpty { return degrees }
                var result: [Int] = []
                result.reserveCapacity(degrees.count * 2)
                for i in 0..<degrees.count {
                    let d = degrees[i]
                    result.append(d)
                    if i + 1 < degrees.count {
                        let next = degrees[i + 1]
                        if abs(next - d) == 2 {
                            result.append((d + next) / 2)
                        }
                    }
                }
                return result
            case "fragment":
                guard degrees.isEmpty == false else { return degrees }
                let fragLen = rng.randint(4, min(7, degrees.count))
                let start = rng.randint(0, degrees.count - fragLen)
                return Array(degrees[start..<(start + fragLen)])
            default:
                return degrees
            }
        }

        let strategies = [
            "original",
            "inversion",
            "sequence_up",
            "retrograde",
            "ornament",
            "sequence_down",
            "fragment",
        ]

        var continuation: [NoteEvent] = []
        continuation.reserveCapacity(Int(continuationDuration * 4.0))
        var currentTime = startTime

        while currentTime < startTime + continuationDuration {
            let phraseIndex = rng.randint(0, phraseDegrees.count - 1)
            let strategy = rng.choice(strategies)

            let degrees = phraseDegrees[phraseIndex]
            let variedDegrees = varyDegrees(degrees: degrees, strategy: strategy)
            let rhythm = applyRhythmicVariation(phrase: phrases[phraseIndex])

            for i in 0..<variedDegrees.count {
                if currentTime >= startTime + continuationDuration {
                    break
                }

                let deg = variedDegrees[i]
                var pitch = analysis.keyRoot + deg
                pitch = quantizeToScale(pitch: pitch, scale: scale, keyRoot: analysis.keyRoot)
                pitch = clampPitch(pitch: pitch, pitchRange: pitchRange)

                var velocity = baseVelocity + rng.randint(-8, 8)
                velocity = max(1, min(127, velocity))

                let dur: Double
                let gap: Double
                if i < rhythm.count {
                    dur = rhythm[i].dur
                    gap = rhythm[i].gap
                } else {
                    dur = 0.3
                    gap = 0.4
                }

                var effectiveGap = gap * rng.uniform(0.85, 1.15)
                var effectiveDur = dur * rng.uniform(0.9, 1.1)

                effectiveGap = min(effectiveGap, maxGap)
                effectiveGap = max(0.08, effectiveGap)
                effectiveDur = min(max(effectiveDur, 0.1), effectiveGap * 0.92)

                continuation.append(
                    NoteEvent(
                        note: pitch,
                        velocity: velocity,
                        start: currentTime,
                        duration: effectiveDur
                    )
                )
                currentTime += effectiveGap
            }
        }

        return continuation
    }
}

private extension Int {
    func mod(_ m: Int) -> Int {
        let r = self % m
        return r >= 0 ? r : r + m
    }
}

private extension Array where Element == Double {
    func average() -> Double? {
        guard isEmpty == false else { return nil }
        return reduce(0.0, +) / Double(count)
    }
}
