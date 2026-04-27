import Foundation

struct AudioSpectrumFrame: Sendable, Equatable, HarmonicBandEnergyProviding {
    let sampleRate: Double
    let windowSize: Int
    let rms: Double
    let noiseFloor: Double
    let onsetScore: Double
    let isOnset: Bool
    let timestamp: Date
    private let frequencyBins: [Double]
    private let magnitudes: [Double]

    init(
        sampleRate: Double,
        windowSize: Int,
        rms: Double,
        noiseFloor: Double,
        onsetScore: Double,
        isOnset: Bool,
        timestamp: Date,
        frequencyBins: [Double] = [],
        magnitudes: [Double] = []
    ) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        self.rms = rms
        self.noiseFloor = noiseFloor
        self.onsetScore = onsetScore
        self.isOnset = isOnset
        self.timestamp = timestamp
        self.frequencyBins = frequencyBins
        self.magnitudes = magnitudes
    }

    func bandEnergy(centerFrequency: Double, toleranceCents: Double) -> Double {
        guard centerFrequency.isFinite, centerFrequency > 0 else { return 0 }
        guard frequencyBins.isEmpty == false, frequencyBins.count == magnitudes.count else { return 0 }
        let range = frequencyRange(centerFrequency: centerFrequency, toleranceCents: toleranceCents, multiplier: 1.0)
        var energy = 0.0
        for index in frequencyBins.indices where frequencyBins[index] >= range.lower && frequencyBins[index] <= range.upper {
            energy += magnitudes[index]
        }
        if energy > 0 { return energy }

        // 真实音高可能落在 FFT bin 之间；最小 bin 宽度兜底避免窄 cents band 漏检。
        guard let nearest = nearestBinIndex(to: centerFrequency) else { return 0 }
        let nearestDistance = abs(frequencyBins[nearest] - centerFrequency)
        return nearestDistance <= binSpacing() ? magnitudes[nearest] : 0
    }

    func surroundingEnergy(centerFrequency: Double, toleranceCents: Double) -> Double {
        guard centerFrequency.isFinite, centerFrequency > 0 else { return 0 }
        guard frequencyBins.isEmpty == false, frequencyBins.count == magnitudes.count else { return 0 }
        let inner = frequencyRange(centerFrequency: centerFrequency, toleranceCents: toleranceCents, multiplier: 1.0)
        let outer = frequencyRange(centerFrequency: centerFrequency, toleranceCents: toleranceCents, multiplier: 3.0)
        var energy = 0.0
        for index in frequencyBins.indices where frequencyBins[index] >= outer.lower && frequencyBins[index] <= outer.upper {
            if frequencyBins[index] >= inner.lower && frequencyBins[index] <= inner.upper { continue }
            energy += magnitudes[index]
        }
        return energy
    }

    private func frequencyRange(centerFrequency: Double, toleranceCents: Double, multiplier: Double) -> (lower: Double, upper: Double) {
        let centLower = centerFrequency * pow(2.0, -abs(toleranceCents) * multiplier / 1200.0)
        let centUpper = centerFrequency * pow(2.0, abs(toleranceCents) * multiplier / 1200.0)
        let centHalfWidth = max((centUpper - centLower) / 2.0, 0)
        let minimumHalfWidth = binSpacing() * 0.75 * max(1.0, multiplier)
        let halfWidth = max(centHalfWidth, minimumHalfWidth)
        return (centerFrequency - halfWidth, centerFrequency + halfWidth)
    }

    private func binSpacing() -> Double {
        guard frequencyBins.count >= 2 else { return sampleRate / Double(max(windowSize, 1)) }
        return max(1e-9, abs(frequencyBins[1] - frequencyBins[0]))
    }

    private func nearestBinIndex(to frequency: Double) -> Int? {
        guard frequencyBins.isEmpty == false else { return nil }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for index in frequencyBins.indices {
            let distance = abs(frequencyBins[index] - frequency)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
