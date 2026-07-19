import Foundation

protocol HarmonicTemplateDetectingProtocol: Sendable {
    func detect(
        spectrumFrame: AudioSpectrumFrame,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        profile: HarmonicTemplateTuningProfile
    ) -> TargetAudioEvidence?
}

struct TargetedHarmonicTemplateDetector: HarmonicTemplateDetectingProtocol {
    private let templateProvider: HarmonicTemplateProvider
    private let scorer: HarmonicTemplateScorer

    init(
        templateProvider: HarmonicTemplateProvider = HarmonicTemplateProvider(),
        scorer: HarmonicTemplateScorer = HarmonicTemplateScorer()
    ) {
        self.templateProvider = templateProvider
        self.scorer = scorer
    }

    func detect(
        spectrumFrame: AudioSpectrumFrame,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        profile: HarmonicTemplateTuningProfile
    ) -> TargetAudioEvidence? {
        let templates = templateProvider.makeTemplates(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongCandidateMIDINotes,
            profile: profile
        )
        let results = scorer.score(
            templates: templates,
            energyProvider: spectrumFrame,
            profile: profile
        )
        return makeEvidence(
            from: results,
            spectrumFrame: spectrumFrame,
            targetMIDINotes: expectedMIDINotes,
            generation: generation,
            suppressing: suppressing,
            profile: profile
        )
    }

    private func makeEvidence(
        from results: [TemplateMatchResult],
        spectrumFrame: AudioSpectrumFrame,
        targetMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        profile: HarmonicTemplateTuningProfile
    ) -> TargetAudioEvidence? {
        guard suppressing == false else { return nil }
        guard spectrumFrame.rms >= profile.minimumRMS else { return nil }
        guard spectrumFrame.isOnset || spectrumFrame.onsetScore >= profile.onsetThreshold else {
            return nil
        }
        let qualified = results.filter { result in
            result.role != .octaveDebug
                && result.confidence >= profile.minimumConfidence
                && result.tonalRatio >= profile.minimumTonalRatio
                && result.dominanceOverWrong >= profile.minimumDominance
        }
        let targetConfidence = qualified.reduce(into: [Int: Double]()) { output, result in
            guard result.role == .expected else { return }
            output[result.midiNote] = max(output[result.midiNote] ?? 0, result.confidence)
        }
        let wrongConfidence = qualified.reduce(into: [Int: Double]()) { output, result in
            guard result.role == .wrongCandidate else { return }
            output[result.midiNote] = max(output[result.midiNote] ?? 0, result.confidence)
        }
        return TargetAudioEvidence(
            targetMIDINotes: targetMIDINotes,
            targetConfidenceByMIDINote: targetConfidence,
            wrongConfidenceByMIDINote: wrongConfidence,
            confidence: results
                .filter { $0.role != .octaveDebug }
                .map(\.confidence)
                .max(),
            onsetScore: spectrumFrame.onsetScore,
            isOnset: spectrumFrame.isOnset,
            timestamp: spectrumFrame.timestamp,
            generation: generation
        )
    }
}
