import Foundation

protocol HarmonicBandEnergyProviding: Sendable {
    var rms: Double { get }
    var noiseFloor: Double { get }

    func bandEnergy(centerFrequency: Double, toleranceCents: Double) -> Double
    func surroundingEnergy(centerFrequency: Double, toleranceCents: Double) -> Double
}

extension HarmonicBandEnergyProviding {
    var rms: Double { 0 }
    var noiseFloor: Double { 0 }
}
