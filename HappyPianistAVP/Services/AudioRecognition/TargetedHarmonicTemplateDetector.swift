import Foundation

protocol HarmonicTemplateDetectingProtocol: Sendable {
    func detect(
        spectrumFrame: AudioSpectrumFrame,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        profile: HarmonicTemplateTuningProfile
    ) -> [DetectedNoteEvent]
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
    ) -> [DetectedNoteEvent] {
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
        return makeEvents(
            from: results,
            spectrumFrame: spectrumFrame,
            generation: generation,
            suppressing: suppressing,
            profile: profile
        )
    }

    private func makeEvents(
        from results: [TemplateMatchResult],
        spectrumFrame: AudioSpectrumFrame,
        generation: Int,
        suppressing: Bool,
        profile: HarmonicTemplateTuningProfile
    ) -> [DetectedNoteEvent] {
        guard suppressing == false else { return [] }
        guard spectrumFrame.rms >= profile.minimumRMS else { return [] }
        guard spectrumFrame.isOnset || spectrumFrame.onsetScore >= profile.onsetThreshold else {
            return []
        }
        return results.compactMap { result in
            guard result.role != .octaveDebug else { return nil }
            guard result.confidence >= profile.minimumConfidence else { return nil }
            guard result.tonalRatio >= profile.minimumTonalRatio else { return nil }
            guard result.dominanceOverWrong >= profile.minimumDominance else { return nil }
            return DetectedNoteEvent(
                midiNote: result.midiNote,
                confidence: result.confidence,
                onsetScore: spectrumFrame.onsetScore,
                isOnset: spectrumFrame.isOnset,
                timestamp: spectrumFrame.timestamp,
                generation: generation
            )
        }
    }
}
