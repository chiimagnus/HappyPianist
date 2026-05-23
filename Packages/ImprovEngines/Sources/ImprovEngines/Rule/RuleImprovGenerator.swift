import Foundation
import ImprovProtocol

public struct RuleImprovGenerator: Sendable {
    public init() {}

    public func generateRuleResponse(
        notes: [ImprovDialogueNote],
        params: ImprovGenerateParams,
        sessionID _: String?,
        seed: UInt64
    ) -> [ImprovDialogueNote] {
        let inputEvents = notes.map { RuleNoteEvent(note: $0.note, velocity: $0.velocity, time: $0.time, duration: $0.duration) }
        let responseSeconds = deriveResponseLengthSeconds(params: params)
        let contextSeconds = min(8.0, maxPhraseEndSeconds(notes: inputEvents) + 1.0)

        let result = runRuleImproviser(
            notes: inputEvents,
            responseSeconds: responseSeconds,
            style: "pop",
            contextSeconds: contextSeconds,
            mode: "motif",
            secondsPerMeasure: 0.0,
            seed: seed
        )

        return result.notes.map { event in
            ImprovDialogueNote(
                note: max(0, min(127, event.note)),
                velocity: max(1, min(127, event.velocity)),
                time: max(0.0, event.time),
                duration: max(0.01, event.duration)
            )
        }
    }

    public func deriveResponseLengthSeconds(params: ImprovGenerateParams) -> Double {
        let seconds = Double(params.maxTokens) / 64.0
        return max(2.0, min(seconds, 12.0))
    }

    // MARK: - Core (ported from rule_backend.py)

    public func runRuleImproviser(
        notes: [RuleNoteEvent],
        responseSeconds: Double,
        style: String = "pop",
        contextSeconds: Double = 4.0,
        mode: String = "rhythm_lock",
        secondsPerMeasure: Double = 0.0,
        seed: UInt64
    ) -> RuleResult {
        let normalizedStyle = RuleConstants.styleRules[style] != nil ? style : "pop"
        let normalizedMode = (mode == "rhythm_lock" || mode == "motif") ? mode : "rhythm_lock"
        let rule = RuleConstants.styleRules[normalizedStyle] ?? RuleConstants.styleRules["pop"]!

        let useProgression = secondsPerMeasure > 0
        let effectiveSPM = secondsPerMeasure > 0 ? secondsPerMeasure : 2.0

        let tonal = inferTonalCenter(notes: notes)
        let singleChord = inferChordFromNotes(notes: notes, tonal: tonal, contextSeconds: contextSeconds)

        var rng = PythonRandom(seed: seed)

        let inputChords: [RuleChordGuess]
        let responseMeasureCount: Int
        let predictedChords: [RuleChordGuess]
        if useProgression {
            let inputDuration = notes.map { $0.time + $0.duration }.max() ?? effectiveSPM
            let inputMeasureCount = max(1, Int((inputDuration / effectiveSPM).rounded(.toNearestOrEven)))
            inputChords = inferChordsPerMeasure(
                notes: notes,
                tonal: tonal,
                secondsPerMeasure: effectiveSPM,
                totalMeasures: inputMeasureCount
            )
            responseMeasureCount = max(1, Int(ceil(responseSeconds / effectiveSPM)))
            predictedChords = predictNextChords(
                inputChords: inputChords,
                tonal: tonal,
                count: responseMeasureCount,
                rng: &rng
            )
        } else {
            inputChords = [singleChord]
            responseMeasureCount = 1
            predictedChords = [singleChord]
        }

        let beatOffset = useProgression ? computeBeatOffset(notes: notes, secondsPerMeasure: effectiveSPM) : 0.0

        var measureScales: [[Int]] = []
        var measureChordPCs: [[Int]] = []
        if useProgression {
            for chord in predictedChords {
                let fullScale = scaleForChord(chord: chord, tonal: tonal, style: normalizedStyle)
                let filteredScale = styleFilteredScale(fullScale: fullScale, style: normalizedStyle)
                measureScales.append(filteredScale)
                measureChordPCs.append(chord.pitchClasses)
            }
        } else {
            let fallbackScale = styleScale(rootPC: tonal.rootPC, mode: tonal.mode, style: normalizedStyle)
            measureScales = [fallbackScale]
            measureChordPCs = [singleChord.pitchClasses]
        }

        let chordPitchClasses = singleChord.pitchClasses
        let strongPitchClasses = pitchClassSet(rootPC: tonal.rootPC, intervals: rule.strongDegrees)

        let (_, _, center) = deriveRegister(notes: notes)
        let motifSources = recentMotifSourceNotes(
            notes: notes,
            contextSeconds: contextSeconds,
            secondsPerMeasure: effectiveSPM
        )
        let motif: [(time: Double, duration: Double, velocity: Int)] = motifSources.map { ($0.time, $0.duration, $0.velocity) }

        let texture = analyzeTexture(notes: notes, contextSeconds: contextSeconds, secondsPerMeasure: effectiveSPM)

        let sortedNotes = notes.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }
        var sourcePitches = sortedNotes.suffix(8).map(\.note)
        if sourcePitches.isEmpty {
            sourcePitches = [center, center + 2, center + 4, center + 7]
        }
        let baseVelocity: Int = {
            guard notes.isEmpty == false else { return 82 }
            let sum = notes.reduce(0) { $0 + $1.velocity }
            return sum / max(1, notes.count)
        }()

        let velocitySpread: Int = {
            guard notes.isEmpty == false else { return 30 }
            let velocities = notes.map(\.velocity)
            return (velocities.max() ?? 0) - (velocities.min() ?? 0)
        }()
        let flatVelocity = velocitySpread < 15

        let sourceArticRatio = computeSourceArticulationRatio(motif: motif)

        var prevMelodyPitch = (texture.melodyLow + texture.melodyHigh) / 2
        let maxMelodyStep = deriveMaxMelodyStep(
            notes: notes,
            texture: texture,
            contextSeconds: contextSeconds,
            fallback: 7
        )

        var prevBassPitch = 0
        if notes.isEmpty == false {
            let recentLow = notes.suffix(8).map(\.note).min() ?? 0
            if recentLow <= texture.bassHigh {
                prevBassPitch = recentLow
            }
        }
        var prevChordRootPC = -1

        var output: [RuleNoteEvent] = []
        output.reserveCapacity(Int(max(16, responseSeconds * 8.0)))

        let promptFingerprints: Set<PitchFingerprint> = Set(notes.map { note in
            PitchFingerprint(
                pitch: note.note,
                time: roundTo(note.time, decimals: 2),
                duration: roundTo(note.duration, decimals: 2)
            )
        })

        let rawCycleLen = max((motif.last?.time ?? 0) + (motif.last?.duration ?? 0), 0.5)
        let cycleLen: Double = {
            if effectiveSPM > 0, useProgression {
                let measureCount = max(1, Int((rawCycleLen / effectiveSPM).rounded(.toNearestOrEven)))
                return effectiveSPM * Double(measureCount)
            }
            return rawCycleLen
        }()

        let minOnsetGap: Double = {
            guard motif.count >= 2 else { return cycleLen }
            let onsetGaps = (0 ..< (motif.count - 1))
                .map { motif[$0 + 1].time - motif[$0].time }
                .filter { $0 > 0 }
            return onsetGaps.min() ?? cycleLen
        }()

        let density = rule.density
        var cycleIndex = 0

        while true {
            let cycleStart = beatOffset + Double(cycleIndex) * cycleLen
            if cycleStart >= responseSeconds { break }

            for motifIndex in 0 ..< motif.count {
                let motifOnset = motif[motifIndex].time
                let motifDuration = motif[motifIndex].duration
                let motifVelocity = motif[motifIndex].velocity

                if normalizedMode == "motif", density < 1.0 {
                    let denom = max(0.25, 1.0 - density)
                    let stride = max(1, Int((1.0 / denom).rounded(.toNearestOrEven)))
                    if (cycleIndex + motifIndex).isMultiple(of: stride), motifIndex != 0, motifIndex != motif.count - 1 {
                        continue
                    }
                }

                let timeSec = roundTo(cycleStart + motifOnset, decimals: 3)
                if timeSec >= responseSeconds { continue }

                let responseMeasureIdx = min(
                    max(0, Int((timeSec - beatOffset) / max(effectiveSPM, 0.0001))),
                    responseMeasureCount - 1
                )

                let currentChordPCs = measureChordPCs[responseMeasureIdx]
                let currentScale = measureScales[responseMeasureIdx]
                let currentChord = predictedChords[responseMeasureIdx]

                let strong = isStrongPosition(
                    timeSec: timeSec,
                    responseSeconds: responseSeconds,
                    secondsPerMeasure: effectiveSPM,
                    beatOffset: beatOffset
                )
                let direction = cycleIndex.isMultiple(of: 2) ? 1 : -1

                let sourceNote = motifSources[motifIndex % motifSources.count]
                let sourcePitch = normalizedMode == "rhythm_lock"
                    ? sourceNote.note
                    : sourcePitches[(cycleIndex + motifIndex) % sourcePitches.count]

                let pitch: Int
                let startTime: Double
                let duration: Double
                let velocity: Int

                if normalizedMode == "rhythm_lock" {
                    var allowed = strong ? currentChordPCs : currentScale
                    if strong == false, ["blues", "rock", "funk"].contains(normalizedStyle) {
                        allowed = Array(Set(allowed).union(Set(currentChordPCs))).sorted()
                    }

                    var target = sourcePitch + direction * (strong ? 4 : 2 + (motifIndex % 2) * 2)
                    if motifIndex == motif.count - 1 || timeSec >= responseSeconds - 0.5 {
                        target = sourcePitch + direction * 3
                        allowed = currentChordPCs
                    }

                    var melodyLow = max(texture.melodyLow, prevMelodyPitch - maxMelodyStep)
                    var melodyHigh = min(texture.melodyHigh, prevMelodyPitch + maxMelodyStep)
                    if strong {
                        melodyLow = max(texture.melodyLow, prevMelodyPitch - maxMelodyStep - 3)
                        melodyHigh = min(texture.melodyHigh, prevMelodyPitch + maxMelodyStep + 3)
                    }
                    if melodyLow > melodyHigh {
                        melodyLow = texture.melodyLow
                        melodyHigh = texture.melodyHigh
                    }

                    var chosen = nearestPitch(target: target, allowedPitchClasses: allowed, low: melodyLow, high: melodyHigh)
                    if chosen == prevMelodyPitch, strong == false {
                        chosen = nearestPitch(target: chosen + direction * 2, allowedPitchClasses: allowed, low: melodyLow, high: melodyHigh)
                    }

                    startTime = timeSec
                    duration = roundTo(min(motifDuration, max(0.08, responseSeconds - startTime)), decimals: 3)
                    chosen = avoidPromptFingerprint(
                        pitch: chosen,
                        startTime: startTime,
                        duration: duration,
                        target: target + direction * 4,
                        allowedPitchClasses: allowed,
                        low: melodyLow,
                        high: melodyHigh,
                        promptFingerprints: promptFingerprints
                    )
                    pitch = chosen
                    velocity = styledVelocity(
                        baseVelocity: motifVelocity,
                        style: normalizedStyle,
                        index: output.count,
                        strong: strong,
                        flatVelocity: flatVelocity
                    )
                } else {
                    var target = sourcePitch + direction * (2 + (motifIndex % 3))
                    let currentStrongPCs = currentChord.pitchClasses
                    let allowed = strong ? currentStrongPCs : currentScale
                    if ["funk", "blues", "rock"].contains(normalizedStyle), strong == false {
                        target += rng.choice([-2, 0, 2])
                    }

                    var melodyLow = max(texture.melodyLow, prevMelodyPitch - maxMelodyStep)
                    var melodyHigh = min(texture.melodyHigh, prevMelodyPitch + maxMelodyStep)
                    if melodyLow > melodyHigh {
                        melodyLow = texture.melodyLow
                        melodyHigh = texture.melodyHigh
                    }

                    var chosen = nearestPitch(target: target, allowedPitchClasses: allowed, low: melodyLow, high: melodyHigh)
                    if chosen == prevMelodyPitch, strong == false {
                        chosen = nearestPitch(target: chosen + direction * 2, allowedPitchClasses: currentScale, low: melodyLow, high: melodyHigh)
                    }

                    startTime = humanizedTime(timeSec: timeSec, style: normalizedStyle, index: output.count)
                    if sourceArticRatio > 0.05 {
                        duration = min(motifDuration, max(0.08, responseSeconds - startTime))
                    } else {
                        duration = min(styledDuration(duration: motifDuration, style: normalizedStyle), max(0.08, responseSeconds - startTime))
                    }

                    chosen = avoidPromptFingerprint(
                        pitch: chosen,
                        startTime: startTime,
                        duration: duration,
                        target: chosen + direction * 4,
                        allowedPitchClasses: allowed,
                        low: melodyLow,
                        high: melodyHigh,
                        promptFingerprints: promptFingerprints
                    )
                    pitch = chosen
                    velocity = styledVelocity(
                        baseVelocity: (baseVelocity + motifVelocity) / 2,
                        style: normalizedStyle,
                        index: output.count,
                        strong: strong,
                        flatVelocity: flatVelocity
                    )
                }

                prevMelodyPitch = pitch

                let (voicing, bassUsed) = generateVoicing(
                    melodyPitch: pitch,
                    chordPCs: currentChordPCs,
                    scalePCs: currentScale,
                    texture: texture,
                    onsetIndex: motifIndex + cycleIndex * motif.count,
                    duration: duration,
                    velocity: velocity,
                    timeSec: startTime,
                    strong: strong,
                    prevBassPitch: prevBassPitch,
                    currentChordRootPC: currentChord.rootPC,
                    prevChordRootPC: prevChordRootPC,
                    secondsPerMeasure: useProgression ? effectiveSPM : 0.0,
                    beatOffset: beatOffset,
                    minOnsetGap: minOnsetGap
                )

                if bassUsed > 0 { prevBassPitch = bassUsed }
                prevChordRootPC = currentChord.rootPC
                output.append(contentsOf: voicing)
            }

            cycleIndex += 1
        }

        if output.isEmpty == false {
            let lastTime = output.map(\.time).max() ?? 0
            let lastNotes = output.filter { abs($0.time - lastTime) < 0.01 }
            if let melodyNote = lastNotes.max(by: { $0.note < $1.note }) {
                let finalChordPCs = measureChordPCs.last ?? chordPitchClasses
                let finalAllowed = normalizedMode == "rhythm_lock" ? finalChordPCs : (predictedChords.last?.pitchClasses ?? strongPitchClasses)
                let finalPitch = nearestPitch(target: melodyNote.note, allowedPitchClasses: finalAllowed, low: texture.melodyLow, high: texture.melodyHigh)
                if let index = output.firstIndex(where: { note in
                    note.note == melodyNote.note
                        && note.velocity == melodyNote.velocity
                        && note.time == melodyNote.time
                        && note.duration == melodyNote.duration
                }) {
                    output.remove(at: index)
                }
                output.append(
                    RuleNoteEvent(
                        note: finalPitch,
                        velocity: melodyNote.velocity,
                        time: melodyNote.time,
                        duration: normalizedMode == "rhythm_lock"
                            ? melodyNote.duration
                            : max(melodyNote.duration, min(0.4, responseSeconds - melodyNote.time))
                    )
                )
            }
        }

        output.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if lhs.note != rhs.note { return lhs.note < rhs.note }
            return lhs.duration < rhs.duration
        }

        return RuleResult(notes: output, timings: [:], debug: [:])
    }

    // MARK: - Analysis helpers

    private func maxPhraseEndSeconds(notes: [RuleNoteEvent]) -> Double {
        notes.map { $0.time + $0.duration }.max() ?? 0.0
    }

    private func pitchClassSet(rootPC: Int, intervals: [Int]) -> [Int] {
        Array(Set(intervals.map { (rootPC + $0).mod(12) })).sorted()
    }

    private func chordPitchClasses(rootPC: Int, quality: String) -> [Int] {
        let intervals = RuleConstants.chordQualityIntervals[quality] ?? RuleConstants.chordQualityIntervals["major"]!
        return pitchClassSet(rootPC: rootPC, intervals: intervals)
    }

    private func scaleForChord(chord: RuleChordGuess, tonal: RuleTonalCenter, style: String) -> [Int] {
        let root = chord.rootPC
        let quality = chord.quality
        let interval = (root - tonal.rootPC).mod(12)

        if tonal.mode == "major" {
            if ["major", "major7", "dominant7"].contains(quality) {
                if interval == 0 {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.majorScale)
                } else if interval == 5 {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.lydian)
                } else if interval == 7 {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.mixolydian)
                } else {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.mixolydian)
                }
            } else if ["minor", "minor7"].contains(quality) {
                if interval == 2 {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.dorian)
                } else if interval == 4 {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.phrygian)
                } else if interval == 9 {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.naturalMinorScale)
                } else {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.dorian)
                }
            } else if quality == "diminished" {
                return pitchClassSet(rootPC: root, intervals: [0, 2, 3, 5, 6, 8, 9, 11])
            } else if quality == "sus4" {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.mixolydian)
            } else if quality == "sus2" {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.majorScale)
            } else {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.majorScale)
            }
        }

        if ["minor", "minor7"].contains(quality) {
            if interval == 0 {
                if ["funk", "rnb", "neo_soul"].contains(style) {
                    return pitchClassSet(rootPC: root, intervals: RuleConstants.dorian)
                }
                return pitchClassSet(rootPC: root, intervals: RuleConstants.naturalMinorScale)
            } else if interval == 5 {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.dorian)
            } else {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.dorian)
            }
        } else if ["major", "major7", "dominant7"].contains(quality) {
            if interval == 3 {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.majorScale)
            } else if interval == 8 {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.lydian)
            } else if interval == 7 {
                return pitchClassSet(rootPC: tonal.rootPC, intervals: RuleConstants.harmonicMinor)
            } else if interval == 10 {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.mixolydian)
            } else {
                return pitchClassSet(rootPC: root, intervals: RuleConstants.mixolydian)
            }
        } else if quality == "diminished" {
            return pitchClassSet(rootPC: root, intervals: [0, 2, 3, 5, 6, 8, 9, 11])
        } else if ["sus4", "sus2"].contains(quality) {
            return pitchClassSet(rootPC: root, intervals: RuleConstants.naturalMinorScale)
        }

        return pitchClassSet(rootPC: root, intervals: RuleConstants.naturalMinorScale)
    }

    private func styleScale(rootPC: Int, mode: String, style: String) -> [Int] {
        let rule = RuleConstants.styleRules[style] ?? RuleConstants.styleRules["pop"]!
        let scaleName = rule.scale

        switch scaleName {
        case "major_pentatonic":
            return pitchClassSet(
                rootPC: rootPC,
                intervals: mode == "major" ? RuleConstants.majorPentatonic : RuleConstants.minorPentatonic
            )
        case "major_add9":
            return pitchClassSet(rootPC: rootPC, intervals: Array(Set(RuleConstants.majorPentatonic + [2])).sorted())
        case "minor_blues", "blues":
            return pitchClassSet(rootPC: rootPC, intervals: RuleConstants.bluesScale)
        case "minor_pentatonic":
            return pitchClassSet(rootPC: rootPC, intervals: RuleConstants.minorPentatonic)
        case "dorian":
            return pitchClassSet(rootPC: rootPC, intervals: RuleConstants.dorian)
        case "dorian_color":
            return pitchClassSet(rootPC: rootPC, intervals: Array(Set(RuleConstants.dorian + [5])).sorted())
        default:
            return pitchClassSet(rootPC: rootPC, intervals: RuleConstants.majorPentatonic)
        }
    }

    private func styleFilteredScale(fullScale: [Int], style: String) -> [Int] {
        let rule = RuleConstants.styleRules[style] ?? RuleConstants.styleRules["pop"]!
        let scaleName = rule.scale

        if ["major_pentatonic", "minor_pentatonic", "major_add9"].contains(scaleName), fullScale.count > 6 {
            let root = fullScale.first ?? 0
            let isMinorish = fullScale.contains { (($0 - root).mod(12)) == 3 }
            let penta = Set(
                pitchClassSet(
                    rootPC: root,
                    intervals: isMinorish ? RuleConstants.minorPentatonic : RuleConstants.majorPentatonic
                )
            )
            let filtered = fullScale.filter { penta.contains($0) }
            return filtered.count >= 4 ? filtered : fullScale
        }

        return fullScale
    }

    private func inferTonalCenter(notes: [RuleNoteEvent]) -> RuleTonalCenter {
        guard notes.isEmpty == false else {
            return RuleTonalCenter(rootPC: 0, mode: "major")
        }

        var weights = Array(repeating: 0.0, count: 12)
        let phraseEnd = notes.map { $0.time + $0.duration }.max() ?? 0
        for note in notes {
            let recency = 1.0 + max(0.0, note.time + note.duration - phraseEnd + 4.0) / 4.0
            let durationWeight = max(0.1, min(2.0, note.duration))
            weights[note.note.mod(12)] += durationWeight * recency
        }

        var bestRoot = 0
        var bestMode = "major"
        var bestScore = -Double.greatestFiniteMagnitude

        for root in 0 ..< 12 {
            for (mode, intervals) in [("major", RuleConstants.majorScale), ("minor", RuleConstants.naturalMinorScale)] {
                let scale = Set(intervals.map { (root + $0).mod(12) })
                let triad = Set((mode == "major" ? [0, 4, 7] : [0, 3, 7]).map { (root + $0).mod(12) })
                var score = 0.0
                for pc in scale {
                    score += weights[pc] * (triad.contains(pc) ? 1.5 : 1.0)
                }
                score += weights[root] * 0.75
                if score > bestScore {
                    bestRoot = root
                    bestMode = mode
                    bestScore = score
                }
            }
        }

        return RuleTonalCenter(rootPC: bestRoot, mode: bestMode)
    }

    private func inferChordFromNotes(
        notes: [RuleNoteEvent],
        tonal: RuleTonalCenter,
        contextSeconds: Double
    ) -> RuleChordGuess {
        guard notes.isEmpty == false else {
            let quality = tonal.mode == "minor" ? "minor" : "major"
            return RuleChordGuess(rootPC: tonal.rootPC, quality: quality, score: 0.0, pitchClasses: chordPitchClasses(rootPC: tonal.rootPC, quality: quality))
        }

        let phraseEnd = notes.map { $0.time + $0.duration }.max() ?? 0
        let start = max(0.0, phraseEnd - max(0.25, contextSeconds))
        var recent = notes.filter { $0.time + $0.duration > start }
        if recent.isEmpty { recent = notes }

        var weights = Array(repeating: 0.0, count: 12)
        for note in recent {
            let durationWeight = max(0.12, min(1.5, note.duration))
            let recency = 1.0 + max(0.0, note.time + note.duration - phraseEnd + contextSeconds) / max(0.25, contextSeconds)
            weights[note.note.mod(12)] += durationWeight * recency
        }

        let totalWeight = weights.reduce(0, +).nonZeroOr(1.0)
        var best = RuleChordGuess(
            rootPC: tonal.rootPC,
            quality: tonal.mode == "minor" ? "minor" : "major",
            score: -1.0,
            pitchClasses: chordPitchClasses(rootPC: tonal.rootPC, quality: tonal.mode == "minor" ? "minor" : "major")
        )

        for root in 0 ..< 12 {
            for (quality, intervals) in RuleConstants.chordQualityIntervals {
                let pitchClasses = chordPitchClasses(rootPC: root, quality: quality)
                let chordSet = Set(pitchClasses)
                let matched = chordSet.reduce(0.0) { $0 + weights[$1] }
                let rootWeight = weights[root]
                let thirdWeight = weights[(root + intervals[1]).mod(12)]
                let fifthWeight = (intervals.count > 2) ? weights[(root + intervals[2]).mod(12)] : 0.0

                var score = matched * 2.0 + rootWeight * 0.5 + min(thirdWeight, fifthWeight) * 0.25
                score -= (totalWeight - matched) * 0.2

                if rootWeight < 0.1 { score -= 0.6 }

                if RuleConstants.qualityBase[quality] != nil {
                    let seventhPC = (root + intervals.last!).mod(12)
                    let seventhWeight = weights[seventhPC]
                    if seventhWeight < 0.3 {
                        score -= 0.5
                    } else if rootWeight < 0.1 {
                        score -= 0.3
                    } else {
                        score += seventhWeight * 0.2
                    }
                }

                if quality == "sus4" || quality == "sus2" {
                    let thirdMajor = (root + 4).mod(12)
                    let thirdMinor = (root + 3).mod(12)
                    if weights[thirdMajor] > 0.3 || weights[thirdMinor] > 0.3 {
                        score -= 0.8
                    }
                }

                if quality == "diminished" || quality == "augmented" {
                    score -= 0.3
                }

                if root == tonal.rootPC { score += 0.15 }
                if (tonal.mode == "major" && quality == "major") || (tonal.mode == "minor" && quality == "minor") {
                    score += 0.05
                }

                if score > best.score {
                    best = RuleChordGuess(rootPC: root, quality: quality, score: score, pitchClasses: pitchClasses)
                }
            }
        }

        return best
    }

    private func inferChordsPerMeasure(
        notes: [RuleNoteEvent],
        tonal: RuleTonalCenter,
        secondsPerMeasure: Double,
        totalMeasures: Int
    ) -> [RuleChordGuess] {
        if notes.isEmpty || secondsPerMeasure <= 0 || totalMeasures <= 0 {
            let quality = tonal.mode == "minor" ? "minor" : "major"
            let `default` = RuleChordGuess(rootPC: tonal.rootPC, quality: quality, score: 0.0, pitchClasses: chordPitchClasses(rootPC: tonal.rootPC, quality: quality))
            return Array(repeating: `default`, count: max(1, totalMeasures))
        }

        var chords: [RuleChordGuess] = []
        chords.reserveCapacity(totalMeasures)

        for measureIndex in 0 ..< totalMeasures {
            let measureStart = Double(measureIndex) * secondsPerMeasure
            let measureEnd = Double(measureIndex + 1) * secondsPerMeasure

            let measureNotes = notes.compactMap { n -> RuleNoteEvent? in
                guard n.time < measureEnd, n.time + n.duration > measureStart else { return nil }
                let time = max(0.0, n.time - measureStart)
                let dur = min(n.duration, measureEnd - max(n.time, measureStart))
                return RuleNoteEvent(note: n.note, velocity: n.velocity, time: time, duration: dur)
            }

            let chord: RuleChordGuess
            if measureNotes.isEmpty == false {
                chord = inferChordFromNotes(notes: measureNotes, tonal: tonal, contextSeconds: secondsPerMeasure)
            } else if let last = chords.last {
                chord = last
            } else {
                let quality = tonal.mode == "minor" ? "minor" : "major"
                chord = RuleChordGuess(rootPC: tonal.rootPC, quality: quality, score: 0.0, pitchClasses: chordPitchClasses(rootPC: tonal.rootPC, quality: quality))
            }
            chords.append(chord)
        }

        return chords
    }

    private func chordToDegree(chord: RuleChordGuess, tonal: RuleTonalCenter) -> Int {
        (chord.rootPC - tonal.rootPC).mod(12)
    }

    private func degreeToChordQuality(degree: Int, mode: String) -> String {
        if mode == "major" {
            let majorDegrees: Set = [0, 5, 7]
            let minorDegrees: Set = [2, 4, 9]
            let dimDegrees: Set = [11]
            if majorDegrees.contains(degree) { return "major" }
            if minorDegrees.contains(degree) { return "minor" }
            if dimDegrees.contains(degree) { return "diminished" }
            return "major"
        }

        let minorDegrees: Set = [0, 5, 7]
        let majorDegrees: Set = [3, 8, 10]
        let dimDegrees: Set = [2]
        if minorDegrees.contains(degree) { return "minor" }
        if majorDegrees.contains(degree) { return "major" }
        if dimDegrees.contains(degree) { return "diminished" }
        return "minor"
    }

    private func chordsMatch(_ a: RuleChordGuess, _ b: RuleChordGuess) -> Bool {
        a.rootPC == b.rootPC
    }

    private func detectLoop(chords: [RuleChordGuess]) -> (isLooping: Bool, loopLength: Int) {
        if chords.count < 2 { return (false, 0) }

        if chords.count >= 2 {
            for loopLen in 1 ... (chords.count / 2) {
                let pattern = Array(chords.prefix(loopLen))
                var isLoop = true
                for i in loopLen ..< chords.count {
                    if chordsMatch(chords[i], pattern[i % loopLen]) == false {
                        isLoop = false
                        break
                    }
                }
                if isLoop { return (true, loopLen) }
            }
        }

        var bestLoopLen = 0
        var bestCoverage = 0

        let maxLoopLen = chords.count - 1
        if maxLoopLen >= 2 {
            for loopLen in 2 ... maxLoopLen {
                for start in 0 ..< (chords.count - loopLen) {
                    let pattern = Array(chords[start ..< (start + loopLen)])
                    var matchCount = 0
                    for i in start ..< chords.count {
                        if chordsMatch(chords[i], pattern[(i - start) % loopLen]) {
                            matchCount += 1
                        } else {
                            break
                        }
                    }
                    let coverage = matchCount
                    if matchCount > loopLen, coverage > bestCoverage {
                        bestCoverage = coverage
                        bestLoopLen = loopLen
                    }
                }
            }
        }

        if bestLoopLen >= 2, Double(bestCoverage) >= Double(chords.count) * 0.6 {
            return (true, bestLoopLen)
        }

        return (false, 0)
    }

    private func findLoopPattern(chords: [RuleChordGuess], loopLength: Int) -> [RuleChordGuess] {
        var bestStart = 0
        var bestMatches = 0

        guard loopLength > 0, chords.count >= loopLength else { return chords }
        for start in 0 ... (chords.count - loopLength) {
            let pattern = Array(chords[start ..< (start + loopLength)])
            var matches = 0
            for i in start ..< chords.count {
                if chordsMatch(chords[i], pattern[(i - start) % loopLength]) {
                    matches += 1
                } else {
                    break
                }
            }
            if matches > bestMatches {
                bestMatches = matches
                bestStart = start
            }
        }

        return Array(chords[bestStart ..< (bestStart + loopLength)])
    }

    private func predictNextChords(
        inputChords: [RuleChordGuess],
        tonal: RuleTonalCenter,
        count: Int,
        rng: inout PythonRandom
    ) -> [RuleChordGuess] {
        if inputChords.isEmpty {
            let quality = tonal.mode == "minor" ? "minor" : "major"
            let `default` = RuleChordGuess(rootPC: tonal.rootPC, quality: quality, score: 1.0, pitchClasses: chordPitchClasses(rootPC: tonal.rootPC, quality: quality))
            return Array(repeating: `default`, count: count)
        }

        let (isLooping, loopLength) = detectLoop(chords: inputChords)
        if isLooping, loopLength > 0 {
            let pattern = findLoopPattern(chords: inputChords, loopLength: loopLength)
            let lastRoot = inputChords.last!.rootPC

            var phase = 0
            for i in 0 ..< loopLength {
                if pattern[i].rootPC == lastRoot {
                    phase = (i + 1) % loopLength
                }
            }

            return (0 ..< count).map { i in
                pattern[(phase + i) % loopLength]
            }
        }

        let transitions = tonal.mode == "major" ? RuleConstants.majorTransitions : RuleConstants.minorTransitions
        var result: [RuleChordGuess] = []
        result.reserveCapacity(count)

        var current = inputChords.last!
        for _ in 0 ..< count {
            let degree = chordToDegree(chord: current, tonal: tonal)

            let candidates: [(next: Int, weight: Double)] = {
                if let direct = transitions[degree] {
                    return direct
                }
                let known = transitions.keys.sorted()
                guard let nearest = known.min(by: { a, b in
                    let da = min(abs(a - degree), 12 - abs(a - degree))
                    let db = min(abs(b - degree), 12 - abs(b - degree))
                    if da != db { return da < db }
                    return a < b
                }) else {
                    return transitions[0] ?? []
                }
                return transitions[nearest] ?? []
            }()

            let total = candidates.reduce(0.0) { $0 + $1.weight }
            let roll = rng.random() * total
            var chosenDegree = candidates.first?.next ?? 0
            var cumulative = 0.0
            for item in candidates {
                cumulative += item.weight
                if roll <= cumulative {
                    chosenDegree = item.next
                    break
                }
            }

            var nextQuality = degreeToChordQuality(degree: chosenDegree, mode: tonal.mode)
            if chosenDegree == 7, tonal.mode == "major" {
                let hadDominant7 = inputChords.contains { chord in
                    chord.quality == "dominant7" && chordToDegree(chord: chord, tonal: tonal) == 7
                }
                if hadDominant7 { nextQuality = "dominant7" }
            }

            let nextRoot = (tonal.rootPC + chosenDegree).mod(12)
            let nextChord = RuleChordGuess(
                rootPC: nextRoot,
                quality: nextQuality,
                score: 1.0,
                pitchClasses: chordPitchClasses(rootPC: nextRoot, quality: nextQuality)
            )
            result.append(nextChord)
            current = nextChord
        }

        return result
    }

    // MARK: - Motif / texture helpers

    private func recentMotifSourceNotes(
        notes: [RuleNoteEvent],
        contextSeconds: Double,
        maxEvents: Int = 10,
        secondsPerMeasure: Double
    ) -> [RuleNoteEvent] {
        if notes.isEmpty {
            return [
                RuleNoteEvent(note: 60, velocity: 80, time: 0.0, duration: 0.35),
                RuleNoteEvent(note: 62, velocity: 78, time: 0.5, duration: 0.35),
                RuleNoteEvent(note: 64, velocity: 84, time: 1.0, duration: 0.5),
                RuleNoteEvent(note: 67, velocity: 76, time: 1.75, duration: 0.35),
            ]
        }

        var effectiveContext = contextSeconds
        var effectiveMax = maxEvents
        if secondsPerMeasure > 0 {
            effectiveContext = max(contextSeconds, secondsPerMeasure)
            effectiveMax = max(10, Int(secondsPerMeasure / 0.15))
        }

        let phraseEnd = notes.map { $0.time + $0.duration }.max() ?? 0.0
        let start = max(0.0, phraseEnd - max(0.25, effectiveContext))
        let sorted = notes.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if lhs.note != rhs.note { return lhs.note < rhs.note }
            return lhs.duration < rhs.duration
        }
        var recent = sorted.filter { $0.time + $0.duration > start }
        if recent.count > effectiveMax { recent = Array(recent.suffix(effectiveMax)) }
        if recent.isEmpty {
            recent = Array(sorted.suffix(maxEvents))
        }

        let motifStart = recent.map(\.time).min() ?? 0.0
        var onsetGroups: [Double: RuleNoteEvent] = [:]
        for note in recent {
            let onset = roundTo(max(0.0, note.time - motifStart), decimals: 3)
            if let existing = onsetGroups[onset] {
                if note.note > existing.note { onsetGroups[onset] = note }
            } else {
                onsetGroups[onset] = note
            }
        }

        var motif: [RuleNoteEvent] = []
        for onset in onsetGroups.keys.sorted() {
            let note = onsetGroups[onset]!
            motif.append(
                RuleNoteEvent(
                    note: note.note,
                    velocity: note.velocity,
                    time: onset,
                    duration: roundTo(max(0.08, note.duration), decimals: 3)
                )
            )
        }

        if motif.count < 2 {
            let previous = motif.last ?? RuleNoteEvent(note: 60, velocity: 80, time: 0.0, duration: 0.35)
            motif.append(
                RuleNoteEvent(
                    note: previous.note + 2,
                    velocity: previous.velocity,
                    time: roundTo(previous.time + 0.5, decimals: 3),
                    duration: 0.35
                )
            )
        }

        return motif
    }

    private func nearestPitch(target: Int, allowedPitchClasses: [Int], low: Int, high: Int) -> Int {
        let candidates = (low ... high).filter { allowedPitchClasses.contains($0.mod(12)) }
        guard candidates.isEmpty == false else { return max(low, min(high, target)) }
        return candidates.min(by: { a, b in
            let da = abs(a - target)
            let db = abs(b - target)
            if da != db { return da < db }
            return a < b
        })!
    }

    private func deriveRegister(notes: [RuleNoteEvent]) -> (low: Int, high: Int, center: Int) {
        if notes.isEmpty { return (54, 74, 64) }
        let pitches = notes.map(\.note).sorted()
        let center = Int((Double(pitches.reduce(0, +)) / Double(pitches.count)).rounded(.toNearestOrEven))
        var low = max(36, (pitches.min() ?? 36) - 5)
        var high = min(96, (pitches.max() ?? 96) + 7)
        if high - low < 12 {
            low = max(36, center - 8)
            high = min(96, center + 8)
        }
        return (low, high, center)
    }

    private struct TextureProfile {
        var avgDensity: Double
        var bassLow: Int
        var bassHigh: Int
        var melodyLow: Int
        var melodyHigh: Int
        var hasBass: Bool
        var hasChord: Bool
        var onsetDensities: [Int]
        var measureDensityTemplate: [(pos: Double, density: Int)]
    }

    private func analyzeTexture(notes: [RuleNoteEvent], contextSeconds: Double, secondsPerMeasure: Double) -> TextureProfile {
        if notes.isEmpty {
            return TextureProfile(
                avgDensity: 1.0,
                bassLow: 36,
                bassHigh: 48,
                melodyLow: 60,
                melodyHigh: 84,
                hasBass: false,
                hasChord: false,
                onsetDensities: [1],
                measureDensityTemplate: []
            )
        }

        let phraseEnd = notes.map { $0.time + $0.duration }.max() ?? 0.0

        var registerContext = contextSeconds
        if secondsPerMeasure > 0 {
            registerContext = max(contextSeconds, secondsPerMeasure * 6)
        }
        let registerStart = max(0.0, phraseEnd - max(0.25, registerContext))
        var registerNotes = notes.filter { $0.time + $0.duration > registerStart }
        if registerNotes.isEmpty { registerNotes = notes }

        var densityContext = contextSeconds
        if secondsPerMeasure > 0 {
            densityContext = max(contextSeconds, secondsPerMeasure * 3)
        }
        let densityStart = max(0.0, phraseEnd - max(0.25, densityContext))
        var recent = notes.filter { $0.time + $0.duration > densityStart }
        if recent.isEmpty { recent = notes }

        let recentSorted = recent.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }

        var onsets: [[RuleNoteEvent]] = []
        var currentGroup: [RuleNoteEvent] = []
        var currentTime = -1.0
        for note in recentSorted {
            if currentTime < 0 || abs(note.time - currentTime) < 0.03 {
                currentGroup.append(note)
                if currentTime < 0 { currentTime = note.time }
            } else {
                if currentGroup.isEmpty == false { onsets.append(currentGroup) }
                currentGroup = [note]
                currentTime = note.time
            }
        }
        if currentGroup.isEmpty == false { onsets.append(currentGroup) }

        if onsets.isEmpty {
            return TextureProfile(
                avgDensity: 1.0,
                bassLow: 36,
                bassHigh: 48,
                melodyLow: 60,
                melodyHigh: 84,
                hasBass: false,
                hasChord: false,
                onsetDensities: [1],
                measureDensityTemplate: []
            )
        }

        let densities = onsets.map(\.count)
        let avgDensity = Double(densities.reduce(0, +)) / Double(densities.count)

        let allPitches = registerNotes.map(\.note).sorted()
        let lowest = allPitches.first ?? 60
        let highest = allPitches.last ?? 72
        let pitchRange = highest - lowest

        var hasBass = false
        var hasChord = false
        let bassLow = max(24, lowest)
        var bassHigh = lowest + max(12, pitchRange / 3)
        var melodyLow = highest - max(12, pitchRange / 3)
        let melodyHigh = min(108, highest)

        let regOnsetsCount = max(onsets.count, 1)
        if pitchRange >= 24 {
            let bassNotes = registerNotes.filter { $0.note <= bassHigh }
            let midNotes = registerNotes.filter { bassHigh < $0.note && $0.note < melodyLow }
            hasBass = Double(bassNotes.count) >= Double(regOnsetsCount) * 0.2
            hasChord = Double(midNotes.count) >= Double(regOnsetsCount) * 0.15 || avgDensity >= 2.5
        } else if pitchRange >= 12 {
            let center = (lowest + highest) / 2
            bassHigh = center
            melodyLow = center
            let bassNotes = registerNotes.filter { $0.note < center }
            hasBass = Double(bassNotes.count) >= Double(regOnsetsCount) * 0.25
        }

        let onsetDensities = densities.count > 10 ? Array(densities.suffix(10)) : densities

        var measureDensityTemplate: [(pos: Double, density: Int)] = []
        if secondsPerMeasure > 0 {
            var positionDensities: [Double: [Int]] = [:]
            for group in onsets {
                let onsetTime = group.map(\.time).min() ?? 0.0
                let rawRel = (onsetTime.truncatingRemainder(dividingBy: secondsPerMeasure)) / secondsPerMeasure
                let relPos = (rawRel * 16).rounded(.toNearestOrEven) / 16
                positionDensities[relPos, default: []].append(group.count)
            }
            for pos in positionDensities.keys.sorted() {
                let vals = positionDensities[pos]!
                let avg = Int((Double(vals.reduce(0, +)) / Double(vals.count)).rounded(.toNearestOrEven))
                measureDensityTemplate.append((pos: pos, density: max(1, avg)))
            }
        }

        return TextureProfile(
            avgDensity: (avgDensity * 100).rounded(.toNearestOrEven) / 100,
            bassLow: bassLow,
            bassHigh: bassHigh,
            melodyLow: melodyLow,
            melodyHigh: melodyHigh,
            hasBass: hasBass,
            hasChord: hasChord,
            onsetDensities: onsetDensities,
            measureDensityTemplate: measureDensityTemplate
        )
    }

    private func generateVoicing(
        melodyPitch: Int,
        chordPCs: [Int],
        scalePCs: [Int],
        texture: TextureProfile,
        onsetIndex: Int,
        duration: Double,
        velocity: Int,
        timeSec: Double,
        strong: Bool,
        prevBassPitch: Int,
        currentChordRootPC: Int,
        prevChordRootPC: Int,
        secondsPerMeasure: Double,
        beatOffset: Double,
        minOnsetGap: Double
    ) -> ([RuleNoteEvent], Int) {
        var result: [RuleNoteEvent] = [RuleNoteEvent(note: melodyPitch, velocity: velocity, time: timeSec, duration: duration)]

        let targetDensity: Int = {
            if secondsPerMeasure > 0, texture.measureDensityTemplate.isEmpty == false {
                let relPos = ((timeSec - beatOffset).truncatingRemainder(dividingBy: secondsPerMeasure)) / secondsPerMeasure
                let best = texture.measureDensityTemplate.min(by: { abs($0.pos - relPos) < abs($1.pos - relPos) })
                return best?.density ?? 1
            }
            let densityIndex = onsetIndex % max(1, texture.onsetDensities.count)
            return texture.onsetDensities[densityIndex]
        }()

        let cappedTargetDensity = min(targetDensity, 4)
        var bassPitchOut = 0
        if cappedTargetDensity <= 1 { return (result, bassPitchOut) }

        var bassCounted = false
        if texture.hasBass, cappedTargetDensity >= 2 {
            let rootPCs = currentChordRootPC >= 0 ? [currentChordRootPC] : chordPCs
            let chordChanged = (prevChordRootPC < 0) || (currentChordRootPC >= 0 && prevChordRootPC >= 0 && currentChordRootPC != prevChordRootPC)
            if prevBassPitch > 0, chordChanged == false {
                let bassPitch = prevBassPitch
                if bassPitch != melodyPitch {
                    let bassVel = max(40, velocity - 10)
                    result.append(RuleNoteEvent(note: bassPitch, velocity: bassVel, time: timeSec, duration: duration))
                    bassPitchOut = bassPitch
                    bassCounted = true
                }
            } else if prevBassPitch > 0 {
                let bassPitch = nearestPitch(target: prevBassPitch, allowedPitchClasses: rootPCs, low: texture.bassLow, high: texture.bassHigh)
                if bassPitch != melodyPitch {
                    let bassVel = max(40, velocity - 10)
                    var maxDur = secondsPerMeasure > 0 ? secondsPerMeasure / 2 : duration
                    if minOnsetGap > 0 {
                        maxDur = min(maxDur, minOnsetGap * 0.95)
                    }
                    let bassDur = max(duration, maxDur)
                    result.append(RuleNoteEvent(note: bassPitch, velocity: bassVel, time: timeSec, duration: bassDur))
                    bassPitchOut = bassPitch
                    bassCounted = true
                }
            } else {
                let bassTarget = texture.bassLow + (texture.bassHigh - texture.bassLow) / 2
                let bassPitch = nearestPitch(target: bassTarget, allowedPitchClasses: rootPCs, low: texture.bassLow, high: texture.bassHigh)
                if bassPitch != melodyPitch {
                    let bassVel = max(40, velocity - 10)
                    var maxDur = secondsPerMeasure > 0 ? secondsPerMeasure / 2 : duration
                    if minOnsetGap > 0 {
                        maxDur = min(maxDur, minOnsetGap * 0.95)
                    }
                    let bassDur = max(duration, maxDur)
                    result.append(RuleNoteEvent(note: bassPitch, velocity: bassVel, time: timeSec, duration: bassDur))
                    bassPitchOut = bassPitch
                    bassCounted = true
                }
            }
        }

        if cappedTargetDensity >= 3, texture.hasChord || strong {
            let chordLow = texture.bassHigh + 1
            let chordHigh = max(chordLow + 6, texture.melodyLow - 1)

            let effectiveCount = result.count + ((bassCounted && result.count == 1) ? 1 : 0)
            let notesToAdd = min(cappedTargetDensity - effectiveCount, 2)
            let chordCenter = (chordLow + chordHigh) / 2

            let chordDur = secondsPerMeasure > 0 ? min(duration, secondsPerMeasure / 4) : duration

            for i in 0 ..< max(0, notesToAdd) {
                let offset = (i - notesToAdd / 2) * 4
                let target = chordCenter + offset
                let allowed = strong ? chordPCs : Array(Set(chordPCs).union(Set(scalePCs))).sorted()
                let interior = nearestPitch(target: target, allowedPitchClasses: allowed, low: chordLow, high: chordHigh)
                let existing = Set(result.map(\.note))
                if existing.contains(interior) == false {
                    let vel = max(40, velocity - 15)
                    result.append(RuleNoteEvent(note: interior, velocity: vel, time: timeSec, duration: chordDur))
                }
            }
        }

        return (result, bassPitchOut)
    }

    // MARK: - Timing / style helpers

    private func isStrongPosition(timeSec: Double, responseSeconds: Double, secondsPerMeasure: Double, beatOffset: Double) -> Bool {
        if secondsPerMeasure > 0 {
            let posInMeasure = (timeSec - beatOffset).modulo(secondsPerMeasure)
            if posInMeasure < secondsPerMeasure * 0.08 || posInMeasure > secondsPerMeasure * 0.92 {
                return true
            }
            let half = secondsPerMeasure / 2
            if abs(posInMeasure - half) < secondsPerMeasure * 0.08 {
                return true
            }
        } else {
            let beat = ((timeSec.truncatingRemainder(dividingBy: 2.0)) * 2).rounded(.toNearestOrEven) / 2
            if abs(beat - 0.0) <= 0.08 {
                return true
            }
        }

        if timeSec >= responseSeconds - 0.6 {
            return true
        }

        return false
    }

    private func computeBeatOffset(notes: [RuleNoteEvent], secondsPerMeasure: Double) -> Double {
        guard notes.isEmpty == false, secondsPerMeasure > 0 else { return 0.0 }

        let lastNoteEnd = notes.map { $0.time + $0.duration }.max() ?? 0.0
        let posInMeasure = lastNoteEnd.truncatingRemainder(dividingBy: secondsPerMeasure)
        let gapToNext = secondsPerMeasure - posInMeasure

        if posInMeasure < secondsPerMeasure * 0.10 { return 0.0 }
        if gapToNext < secondsPerMeasure * 0.10 { return 0.0 }

        let halfMeasure = secondsPerMeasure / 2
        if posInMeasure < halfMeasure {
            let gapToHalf = halfMeasure - posInMeasure
            if gapToHalf < secondsPerMeasure * 0.10 { return 0.0 }
            return gapToHalf
        }

        return gapToNext
    }

    private func humanizedTime(timeSec: Double, style: String, index: Int) -> Double {
        let timing = (RuleConstants.styleRules[style] ?? RuleConstants.styleRules["pop"]!).timing
        if timeSec <= 0 { return 0.0 }

        let offset: Double
        switch timing {
        case "behind":
            offset = 0.018 + Double(index % 2) * 0.006
        case "swing":
            offset = (index % 2 == 0) ? -0.004 : 0.025
        case "tight_16th":
            let values: [Double] = [-0.006, 0.004, 0.0, 0.007]
            offset = values[index % 4]
        default:
            let values: [Double] = [-0.008, 0.006, 0.0]
            offset = values[index % 3]
        }

        return max(0.0, timeSec + offset)
    }

    private func styledDuration(duration: Double, style: String) -> Double {
        let behavior = (RuleConstants.styleRules[style] ?? RuleConstants.styleRules["pop"]!).duration
        switch behavior {
        case "staccato":
            return max(0.06, min(duration * 0.45, 0.22))
        case "short":
            return max(0.08, min(duration * 0.7, 0.4))
        case "legato":
            return max(0.2, min(duration * 1.25, 1.4))
        case "breathy":
            return max(0.1, min(duration * 0.9, 0.8))
        default:
            return max(0.1, min(duration, 0.75))
        }
    }

    private func styledVelocity(baseVelocity: Int, style: String, index: Int, strong: Bool, flatVelocity: Bool) -> Int {
        if flatVelocity {
            let accent = strong ? 5 : 0
            let micro = ((index * 3) % 5) - 2
            let velocity = baseVelocity + accent + micro
            return max(baseVelocity - 5, min(baseVelocity + 12, velocity))
        }

        let range = (RuleConstants.styleRules[style] ?? RuleConstants.styleRules["pop"]!).velocity
        let accent = strong ? 10 : 0
        let contour = ((index * 7) % 17) - 8
        let velocity = baseVelocity + accent + contour
        return max(range.min, min(range.max, velocity))
    }

    private func avoidPromptFingerprint(
        pitch: Int,
        startTime: Double,
        duration: Double,
        target: Int,
        allowedPitchClasses: [Int],
        low: Int,
        high: Int,
        promptFingerprints: Set<PitchFingerprint>
    ) -> Int {
        let fingerprint = PitchFingerprint(pitch: pitch, time: roundTo(startTime, decimals: 2), duration: roundTo(duration, decimals: 2))
        guard promptFingerprints.contains(fingerprint) else { return pitch }

        let candidates = (low ... high).filter { candidate in
            allowedPitchClasses.contains(candidate.mod(12))
                && promptFingerprints.contains(PitchFingerprint(pitch: candidate, time: fingerprint.time, duration: fingerprint.duration)) == false
        }
        guard candidates.isEmpty == false else { return pitch }
        return candidates.min(by: { a, b in
            let da = abs(a - target)
            let db = abs(b - target)
            if da != db { return da < db }
            return a < b
        })!
    }

    private struct PitchFingerprint: Hashable {
        var pitch: Int
        var time: Double
        var duration: Double
    }

    private func computeSourceArticulationRatio(motif: [(time: Double, duration: Double, velocity: Int)]) -> Double {
        guard motif.count >= 2 else { return 0.0 }
        var ratios: [Double] = []
        ratios.reserveCapacity(motif.count)
        for i in 0 ..< (motif.count - 1) {
            let ioi = motif[i + 1].time - motif[i].time
            if ioi > 0.02 {
                ratios.append(min(1.0, motif[i].duration / ioi))
            }
        }
        guard ratios.isEmpty == false else { return 0.0 }
        ratios.sort()
        return ratios[ratios.count / 2]
    }

    private func deriveMaxMelodyStep(notes: [RuleNoteEvent], texture: TextureProfile, contextSeconds: Double, fallback: Int) -> Int {
        guard notes.isEmpty == false else { return fallback }
        let phraseEnd = notes.map { $0.time + $0.duration }.max() ?? 0
        let ctxStart = max(0.0, phraseEnd - max(0.25, contextSeconds))
        let ctxNotes = notes.filter { $0.time + $0.duration > ctxStart }
        guard ctxNotes.isEmpty == false else { return fallback }

        let ctxSorted = ctxNotes.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.note < rhs.note
        }

        var melodyOnsets: [Int] = []
        var groupTime: Double = -1
        var groupHigh = 0

        for n in ctxSorted {
            if groupTime < 0 || abs(n.time - groupTime) < 0.03 {
                if groupTime < 0 { groupTime = n.time }
                if n.note >= texture.melodyLow {
                    groupHigh = max(groupHigh, n.note)
                }
            } else {
                if groupHigh > 0 { melodyOnsets.append(groupHigh) }
                groupTime = n.time
                groupHigh = n.note >= texture.melodyLow ? n.note : 0
            }
        }
        if groupHigh > 0 { melodyOnsets.append(groupHigh) }

        guard melodyOnsets.count >= 3 else { return fallback }
        var intervals: [Int] = []
        intervals.reserveCapacity(melodyOnsets.count)
        for i in 0 ..< (melodyOnsets.count - 1) {
            intervals.append(abs(melodyOnsets[i + 1] - melodyOnsets[i]))
        }
        intervals.sort()
        let p75Index = Int(Double(intervals.count) * 0.75)
        let p75Val = intervals[min(p75Index, intervals.count - 1)]
        return max(5, min(12, p75Val))
    }

    // MARK: - Utilities

    private func roundTo(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded(.toNearestOrEven) / factor
    }
}

private extension Int {
    func mod(_ m: Int) -> Int {
        let r = self % m
        return r >= 0 ? r : r + m
    }
}

private extension Double {
    func modulo(_ m: Double) -> Double {
        guard m != 0 else { return self }
        let r = truncatingRemainder(dividingBy: m)
        return r >= 0 ? r : r + m
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}
