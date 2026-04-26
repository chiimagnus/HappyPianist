import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func detectsA440AsMIDINote69() {
    var detector = GoertzelNoteDetector()
    let samples = makeSineWave(frequency: 440, sampleRate: 44_100, duration: 0.08)

    let results = detector.detect(samples: samples, sampleRate: 44_100, candidateMIDINotes: [69, 70])
    let strongest = results.first

    #expect(strongest?.midiNote == 69)
    #expect((strongest?.confidence ?? 0) > 0.8)
}

@Test
func keepsMIDINote69ForPlus20CentsDetune() {
    var detector = GoertzelNoteDetector()
    let frequency = 440.0 * pow(2.0, 20.0 / 1200.0)
    let samples = makeSineWave(frequency: frequency, sampleRate: 44_100, duration: 0.08)

    let results = detector.detect(samples: samples, sampleRate: 44_100, candidateMIDINotes: [69, 70])
    let strongest = results.first

    #expect(strongest?.midiNote == 69)
}

@Test
func doesNotTreatAdjacentSemitoneAsSameMIDINote() {
    var detector = GoertzelNoteDetector()
    let samples = makeSineWave(frequency: 466.1638, sampleRate: 44_100, duration: 0.08)

    let results = detector.detect(samples: samples, sampleRate: 44_100, candidateMIDINotes: [69, 70])
    let strongest = results.first

    #expect(strongest?.midiNote == 70)
}

@Test
func reportsWrongCandidateWhenItsEnergyDominates() {
    var detector = GoertzelNoteDetector()
    let expectedSamples = makeSineWave(frequency: 440, sampleRate: 44_100, duration: 0.08, amplitude: 0.35)
    let wrongSamples = makeSineWave(frequency: 466.1638, sampleRate: 44_100, duration: 0.08, amplitude: 0.85)
    let mixed = zip(expectedSamples, wrongSamples).map(+)

    let results = detector.detect(samples: mixed, sampleRate: 44_100, candidateMIDINotes: [69, 70])
    let strongest = results.first

    #expect(strongest?.midiNote == 70)
    #expect((results.first { $0.midiNote == 70 }?.rawEnergy ?? 0) > (results.first { $0.midiNote == 69 }?.rawEnergy ?? 0))
}

@Test
func lowInputNoiseDoesNotProduceMatchConfidence() {
    var detector = GoertzelNoteDetector()
    let samples = (0 ..< 3_528).map { index in
        Float(sin(Double(index) * 0.37)) * 0.0001
    }

    let results = detector.detect(samples: samples, sampleRate: 44_100, candidateMIDINotes: [60, 61, 62])

    #expect(results.allSatisfy { $0.confidence == 0 })
    #expect(results.allSatisfy { $0.isOnset == false })
}

private func makeSineWave(
    frequency: Double,
    sampleRate: Double,
    duration: Double,
    amplitude: Float = 1.0
) -> [Float] {
    let sampleCount = Int(sampleRate * duration)
    return (0 ..< sampleCount).map { index in
        let t = Double(index) / sampleRate
        return amplitude * Float(sin(2 * .pi * frequency * t))
    }
}

@Test
func broadbandNoiseDoesNotProduceHighConfidenceDetection() {
    var detector = GoertzelNoteDetector()
    let samples = (0 ..< 4_096).map { index in
        let value = sin(Double(index) * 1.37) + sin(Double(index) * 2.91) + sin(Double(index) * 4.73)
        return Float(value * 0.08)
    }

    let results = detector.detect(samples: samples, sampleRate: 44_100, candidateMIDINotes: [60, 61, 62, 63])

    #expect(results.allSatisfy { $0.confidence < 0.2 })
    #expect(results.allSatisfy { $0.isOnset == false })
}
