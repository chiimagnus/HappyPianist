import Foundation
import Testing

@testable import HappyPianistAVP

struct TargetedHarmonicTemplateDetectorTests {
    @Test func harmonicSignalProducesExpectedEvent() throws {
        let samples = SyntheticAudioFixtures.harmonic(midiNote: 60, attack: true)
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60],
            wrongCandidateMIDINotes: [61],
            generation: 3,
            suppressing: false,
            profile: .lowLatencyDefault
        )
        #expect(events.contains { $0.midiNote == 60 && $0.generation == 3 && $0.isOnset })
    }

    @Test func suppressWindowBlocksEvents() throws {
        let samples = SyntheticAudioFixtures.harmonic(midiNote: 60, attack: true)
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60],
            wrongCandidateMIDINotes: [61],
            generation: 3,
            suppressing: true,
            profile: .lowLatencyDefault
        )
        #expect(events.isEmpty)
    }

    @Test func sustainedHarmonicDoesNotAdvance() throws {
        let samples = SyntheticAudioFixtures.harmonic(midiNote: 60, attack: false)
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60],
            wrongCandidateMIDINotes: [61],
            generation: 4,
            suppressing: false,
            profile: .lowLatencyDefault
        )
        #expect(events.isEmpty)
    }

    @Test func broadbandNoiseDoesNotProduceEvents() throws {
        let samples = SyntheticAudioFixtures.broadbandNoise(amplitude: 0.12)
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60],
            wrongCandidateMIDINotes: [61],
            generation: 5,
            suppressing: false,
            profile: .lowLatencyDefault
        )
        #expect(events.isEmpty)
    }

    @Test func adjacentSemitoneDoesNotEmitExpectedEvent() throws {
        let samples = SyntheticAudioFixtures.harmonic(midiNote: 61, attack: true)
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60],
            wrongCandidateMIDINotes: [61],
            generation: 6,
            suppressing: false,
            profile: .lowLatencyDefault
        )
        #expect(events.contains { $0.midiNote == 60 } == false)
        #expect(events.contains { $0.midiNote == 61 })
    }

    @Test func simpleMajorChordProducesMultipleExpectedEvents() throws {
        let samples = SyntheticAudioFixtures.chord([60, 64, 67], attack: true)
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60, 64, 67],
            wrongCandidateMIDINotes: [61, 63, 66],
            generation: 7,
            suppressing: false,
            profile: .lowLatencyDefault
        )
        let expectedEvents = Set(events.filter { [60, 64, 67].contains($0.midiNote) }.map(\.midiNote))
        #expect(expectedEvents.count >= 2)
    }

    @Test func strongWrongChordEvidenceIsEmitted() throws {
        let expected = SyntheticAudioFixtures.chord([60, 64], attack: true)
        let wrong = SyntheticAudioFixtures.harmonic(midiNote: 61, amplitude: 0.9, attack: true)
        let samples = SyntheticAudioFixtures.mixed([expected, wrong])
        let spectrum = try VDSPAudioSpectrumAnalyzer().analyze(
            samples: samples, sampleRate: 48000, timestamp: .now)
        let events = TargetedHarmonicTemplateDetector().detect(
            spectrumFrame: spectrum,
            expectedMIDINotes: [60, 64, 67],
            wrongCandidateMIDINotes: [61],
            generation: 8,
            suppressing: false,
            profile: .lowLatencyDefault
        )
        #expect(events.contains { $0.midiNote == 61 })
    }
}
