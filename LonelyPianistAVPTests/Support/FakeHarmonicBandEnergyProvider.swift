import Foundation
@testable import LonelyPianistAVP

struct FakeHarmonicBandEnergyProvider: HarmonicBandEnergyProvidingProtocol {
    var rms: Double = 0.03
    var noiseFloor: Double = 0.001
    var bandEnergies: [Int: Double] = [:]
    var surroundingEnergies: [Int: Double] = [:]

    func bandEnergy(centerFrequency: Double, toleranceCents _: Double) -> Double {
        bandEnergies[Self.key(centerFrequency)] ?? 0
    }

    func surroundingEnergy(centerFrequency: Double, toleranceCents _: Double) -> Double {
        surroundingEnergies[Self.key(centerFrequency)] ?? 1
    }

    static func key(_ frequency: Double) -> Int {
        Int(round(frequency))
    }
}
