import Foundation
import Testing
@testable import LonelyPianistAVP

struct VDSPAudioSpectrumAnalyzerTests {
    @Test func attackWindowProducesOnset() throws {
        let samples = SyntheticAudioFixtures.harmonic(midiNote: 60, attack: true)
        let frame = try VDSPAudioSpectrumAnalyzer().analyze(samples: samples, sampleRate: 48_000, timestamp: .now)
        #expect(frame.isOnset)
        #expect(frame.onsetScore >= 0.25)
    }

    @Test func sustainedWindowDoesNotBecomeOnset() throws {
        let samples = SyntheticAudioFixtures.harmonic(midiNote: 60, attack: false)
        let frame = try VDSPAudioSpectrumAnalyzer().analyze(samples: samples, sampleRate: 48_000, timestamp: .now)
        #expect(frame.isOnset == false)
        #expect(frame.onsetScore < 0.25)
    }

    @Test func bandEnergyUsesNearestBinWhenCentsBandFallsBetweenBins() {
        let frame = AudioSpectrumFrame(
            sampleRate: 48_000,
            windowSize: 2048,
            rms: 0.03,
            noiseFloor: 0.001,
            onsetScore: 1,
            isOnset: true,
            timestamp: .now,
            frequencyBins: [250, 281.25, 312.5],
            magnitudes: [0.1, 10, 0.1]
        )
        #expect(frame.bandEnergy(centerFrequency: 261.63, toleranceCents: 20) > 0)
    }
}
