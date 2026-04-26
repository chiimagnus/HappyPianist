import Foundation
import os

struct GoertzelNoteDetection: Sendable, Equatable {
    let midiNote: Int
    let confidence: Double
    let rawEnergy: Double
    let onsetScore: Double
    let isOnset: Bool
}

struct GoertzelNoteDetector {
    var centTolerance: Double = 25
    var onsetThreshold: Double = 0.25
    var minimumInputRMS: Double = 0.01
    var minimumTonalStrength: Double = 0.04


    private static let detuneOffsetsInCents: [Double] = [-25, -12, 0, 12, 25]
    private static let harmonicWeights: [Double] = [1.0, 0.65, 0.45, 0.30]
    private static let performanceLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LonelyPianistAVP",
        category: "Step3AudioPerformance"
    )

    private var previousEnergyByMIDINote: [Int: Double] = [:]

    mutating func detect(
        samples: [Float],
        sampleRate: Double,
        candidateMIDINotes: [Int],
        debugLoggingEnabled: Bool = false
    ) -> [GoertzelNoteDetection] {
        guard samples.isEmpty == false else { return [] }
        guard sampleRate > 0 else { return [] }
        guard candidateMIDINotes.isEmpty == false else { return [] }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let inputRMS = rms(samples)

        var energiesByMIDINote: [Int: Double] = [:]
        for midiNote in Set(candidateMIDINotes) {
            energiesByMIDINote[midiNote] = energyForMIDINote(midiNote, samples: samples, sampleRate: sampleRate)
        }

        if inputRMS < minimumInputRMS {
            previousEnergyByMIDINote = energiesByMIDINote
            return energiesByMIDINote
                .map { midiNote, rawEnergy in
                    GoertzelNoteDetection(
                        midiNote: midiNote,
                        confidence: 0,
                        rawEnergy: rawEnergy,
                        onsetScore: 0,
                        isOnset: false
                    )
                }
                .sorted { lhs, rhs in
                    lhs.rawEnergy > rhs.rawEnergy
                }
        }

        let maxEnergy = energiesByMIDINote.values.max() ?? 0
        let denominator = max(maxEnergy, 1e-9)
        let inputEnergy = max(sumSquares(samples), 1e-9)
        let sampleCount = Double(max(samples.count, 1))

        let results = energiesByMIDINote
            .map { midiNote, rawEnergy in
                let previousEnergy = previousEnergyByMIDINote[midiNote] ?? 0
                let onsetScore = max(0, (rawEnergy - previousEnergy) / max(previousEnergy, 1e-9))
                let relativeCandidateEnergy = rawEnergy / denominator
                let tonalStrength = rawEnergy / max(inputEnergy * sampleCount, 1e-9)
                let tonalScore: Double
                if tonalStrength >= minimumTonalStrength {
                    tonalScore = min(1.0, tonalStrength / 0.25)
                } else {
                    tonalScore = 0
                }
                let confidence = min(1.0, relativeCandidateEnergy * tonalScore)
                previousEnergyByMIDINote[midiNote] = rawEnergy
                return GoertzelNoteDetection(
                    midiNote: midiNote,
                    confidence: confidence,
                    rawEnergy: rawEnergy,
                    onsetScore: onsetScore,
                    isOnset: onsetScore >= onsetThreshold && confidence > 0
                )
            }
            .sorted { lhs, rhs in
                lhs.rawEnergy > rhs.rawEnergy
            }

        if debugLoggingEnabled {
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1_000
            let top = results.first
            Self.performanceLogger.debug(
                "goertzel candidates=\(candidateMIDINotes.count, privacy: .public) ms=\(elapsedMs, privacy: .public) top=\(top?.midiNote ?? -1, privacy: .public) conf=\(top?.confidence ?? 0, privacy: .public)"
            )
        }

        return results
    }

    private func energyForMIDINote(_ midiNote: Int, samples: [Float], sampleRate: Double) -> Double {
        let baseFrequency = midiFrequency(midiNote: midiNote)
        let offsetCandidates = Self.detuneOffsetsInCents.filter { abs($0) <= centTolerance }
        var bestEnergy = 0.0

        for offset in offsetCandidates {
            let offsetFrequency = baseFrequency * pow(2.0, offset / 1200.0)
            let weightedEnergy = harmonicEnergy(baseFrequency: offsetFrequency, samples: samples, sampleRate: sampleRate)
            if weightedEnergy > bestEnergy {
                bestEnergy = weightedEnergy
            }
        }
        return bestEnergy
    }

    private func harmonicEnergy(baseFrequency: Double, samples: [Float], sampleRate: Double) -> Double {
        let nyquist = sampleRate * 0.5
        var result = 0.0

        for (index, weight) in Self.harmonicWeights.enumerated() {
            let harmonicFrequency = baseFrequency * Double(index + 1)
            guard harmonicFrequency < nyquist else { continue }
            result += goertzelMagnitudeSquared(samples: samples, sampleRate: sampleRate, targetFrequency: harmonicFrequency) * weight
        }
        return result
    }

    private func goertzelMagnitudeSquared(samples: [Float], sampleRate: Double, targetFrequency: Double) -> Double {
        let sampleCount = Double(samples.count)
        let k = round((sampleCount * targetFrequency) / sampleRate)
        let omega = (2.0 * .pi * k) / sampleCount
        let coefficient = 2.0 * cos(omega)

        var q0 = 0.0
        var q1 = 0.0
        var q2 = 0.0

        for sample in samples {
            q0 = coefficient * q1 - q2 + Double(sample)
            q2 = q1
            q1 = q0
        }

        return q1 * q1 + q2 * q2 - coefficient * q1 * q2
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(sumSquares(samples) / Double(max(samples.count, 1)))
    }

    private func sumSquares(_ samples: [Float]) -> Double {
        samples.reduce(0.0) { partialResult, sample in
            partialResult + Double(sample * sample)
        }
    }

    private func midiFrequency(midiNote: Int) -> Double {
        440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }
}
