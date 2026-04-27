import Foundation

protocol HarmonicTemplateDetecting: Sendable {
    func detect(
        spectrumFrame: AudioSpectrumFrame,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        requestedMode: PracticeAudioRecognitionDetectorMode,
        profile: HarmonicTemplateTuningProfile
    ) -> TargetedHarmonicDetectionFrame
}

struct TargetedHarmonicTemplateDetector: HarmonicTemplateDetecting {
    private let templateFactory: HarmonicTemplateFactory
    private let scorer: HarmonicTemplateScorer

    init(
        templateFactory: HarmonicTemplateFactory = HarmonicTemplateFactory(),
        scorer: HarmonicTemplateScorer = HarmonicTemplateScorer()
    ) {
        self.templateFactory = templateFactory
        self.scorer = scorer
    }

    func detect(
        spectrumFrame: AudioSpectrumFrame,
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        generation: Int,
        suppressing: Bool,
        requestedMode: PracticeAudioRecognitionDetectorMode,
        profile: HarmonicTemplateTuningProfile
    ) -> TargetedHarmonicDetectionFrame {
        let startedAt = Date().timeIntervalSinceReferenceDate
        let templates = templateFactory.makeTemplates(
            expectedMIDINotes: expectedMIDINotes,
            wrongCandidateMIDINotes: wrongCandidateMIDINotes,
            profile: profile
        )
        let results = scorer.score(
            templates: templates,
            energyProvider: spectrumFrame,
            profile: profile
        )
        let events = makeEvents(
            from: results,
            spectrumFrame: spectrumFrame,
            generation: generation,
            suppressing: suppressing,
            profile: profile
        )
        return TargetedHarmonicDetectionFrame(
            events: events,
            templateMatchResults: results,
            processingDurationMs: ((Date().timeIntervalSinceReferenceDate) - startedAt) * 1000,
            suppressing: suppressing,
            fallbackReason: nil,
            activeDetectorMode: requestedMode == .automatic ? .harmonicTemplate : requestedMode,
            rollingWindowSize: spectrumFrame.windowSize
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
        guard spectrumFrame.isOnset || spectrumFrame.onsetScore >= profile.onsetThreshold else { return [] }
        return results.compactMap { result in
            guard result.role != .octaveDebug else { return nil }
            guard result.confidence >= profile.minimumConfidence else { return nil }
            switch result.role {
                case .expected:
                    guard result.tonalRatio >= profile.minimumTonalRatio else { return nil }
                    guard result.dominanceOverWrong >= profile.minimumDominance else { return nil }
                case .wrongCandidate:
                    guard result.tonalRatio >= profile.minimumTonalRatio else { return nil }
                    guard result.dominanceOverWrong >= profile.minimumDominance else { return nil }
                case .octaveDebug:
                    return nil
            }
            return DetectedNoteEvent(
                midiNote: result.midiNote,
                confidence: result.confidence,
                onsetScore: spectrumFrame.onsetScore,
                isOnset: spectrumFrame.isOnset,
                timestamp: spectrumFrame.timestamp,
                generation: generation,
                source: .audio
            )
        }
    }
}
