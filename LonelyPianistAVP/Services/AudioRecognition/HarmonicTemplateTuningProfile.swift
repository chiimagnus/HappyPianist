import Foundation

struct HarmonicTemplateTuningProfile: Equatable, Sendable {
    let name: String
    let partialWeights: [Int: Double]
    let partialToleranceCents: [Int: Double]
    let minimumConfidence: Double
    let minimumTonalRatio: Double
    let minimumDominance: Double
    let minimumRMS: Double
    let onsetThreshold: Double
    let lowRegisterMIDINoteCutoff: Int
    let lowRegisterWindowSize: Int
    let defaultWindowSize: Int
    let slowProcessingThresholdMs: Double
    let slowFallbackCount: Int
    let errorFallbackCount: Int

    static let lowLatencyDefault = HarmonicTemplateTuningProfile(
        name: "lowLatencyDefault",
        partialWeights: [1: 1.0, 2: 0.70, 3: 0.50, 4: 0.35, 5: 0.25],
        partialToleranceCents: [1: 20, 2: 25, 3: 30, 4: 35, 5: 40],
        minimumConfidence: 0.52,
        minimumTonalRatio: 1.20,
        minimumDominance: 1.05,
        minimumRMS: 0.006,
        onsetThreshold: 0.28,
        lowRegisterMIDINoteCutoff: 48,
        lowRegisterWindowSize: 4096,
        defaultWindowSize: 2048,
        slowProcessingThresholdMs: 30,
        slowFallbackCount: 5,
        errorFallbackCount: 3
    )

    static let strictDefault = HarmonicTemplateTuningProfile(
        name: "strictDefault",
        partialWeights: [1: 1.0, 2: 0.70, 3: 0.50, 4: 0.35, 5: 0.25],
        partialToleranceCents: [1: 18, 2: 22, 3: 26, 4: 30, 5: 34],
        minimumConfidence: 0.66,
        minimumTonalRatio: 1.55,
        minimumDominance: 1.25,
        minimumRMS: 0.008,
        onsetThreshold: 0.35,
        lowRegisterMIDINoteCutoff: 48,
        lowRegisterWindowSize: 4096,
        defaultWindowSize: 2048,
        slowProcessingThresholdMs: 30,
        slowFallbackCount: 5,
        errorFallbackCount: 3
    )

    static let lowRegisterCompensation = HarmonicTemplateTuningProfile(
        name: "lowRegisterCompensation",
        partialWeights: [1: 0.65, 2: 1.00, 3: 0.75, 4: 0.45, 5: 0.30],
        partialToleranceCents: [1: 30, 2: 36, 3: 42, 4: 48, 5: 54],
        minimumConfidence: 0.50,
        minimumTonalRatio: 1.15,
        minimumDominance: 1.00,
        minimumRMS: 0.006,
        onsetThreshold: 0.26,
        lowRegisterMIDINoteCutoff: 52,
        lowRegisterWindowSize: 4096,
        defaultWindowSize: 2048,
        slowProcessingThresholdMs: 30,
        slowFallbackCount: 5,
        errorFallbackCount: 3
    )

    func weight(for harmonicIndex: Int) -> Double {
        max(0, partialWeights[harmonicIndex] ?? 0)
    }

    func toleranceCents(for harmonicIndex: Int) -> Double {
        max(1, partialToleranceCents[harmonicIndex] ?? 25)
    }

    var harmonicIndices: [Int] {
        partialWeights.keys.sorted().filter { weight(for: $0) > 0 }
    }

    func preferredWindowSize(for expectedMIDINotes: [Int]) -> Int {
        guard let lowest = expectedMIDINotes.min() else { return defaultWindowSize }
        return lowest <= lowRegisterMIDINoteCutoff ? lowRegisterWindowSize : defaultWindowSize
    }
}
