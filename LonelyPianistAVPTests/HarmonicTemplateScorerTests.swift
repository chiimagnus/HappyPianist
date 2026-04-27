import Testing
@testable import LonelyPianistAVP

struct HarmonicTemplateScorerTests {
    @Test func expectedDominatesWrongCandidate() {
        let profile = HarmonicTemplateTuningProfile.lowLatencyDefault
        let templates = HarmonicTemplateFactory().makeTemplates(expectedMIDINotes: [60], wrongCandidateMIDINotes: [61], profile: profile)
        var provider = FakeHarmonicBandEnergyProvider()
        for template in templates {
            for partial in template.partials {
                let key = FakeHarmonicBandEnergyProvider.key(partial.centerFrequency)
                provider.bandEnergies[key] = template.role == .expected ? 10 : 1
                provider.surroundingEnergies[key] = 1
            }
        }
        let results = HarmonicTemplateScorer().score(templates: templates, energyProvider: provider, profile: profile)
        let expected = results.first { $0.midiNote == 60 && $0.role == .expected }
        let wrong = results.first { $0.midiNote == 61 && $0.role == .wrongCandidate }
        #expect((expected?.confidence ?? 0) > (wrong?.confidence ?? 1))
        #expect((expected?.dominanceOverWrong ?? 0) > 1)
    }

    @Test func octaveDebugTemplatesAreDebugOnly() {
        let profile = HarmonicTemplateTuningProfile.lowLatencyDefault
        let templates = HarmonicTemplateFactory().makeTemplates(expectedMIDINotes: [60], wrongCandidateMIDINotes: [], profile: profile)
        #expect(templates.filter { $0.role == .octaveDebug }.isEmpty == false)
    }
}


extension HarmonicTemplateScorerTests {
    @Test func incompleteBroadbandLikeEnergyReducesConfidence() {
        let profile = HarmonicTemplateTuningProfile.lowLatencyDefault
        let templates = HarmonicTemplateFactory().makeTemplates(expectedMIDINotes: [60], wrongCandidateMIDINotes: [61], profile: profile)
        var provider = FakeHarmonicBandEnergyProvider(rms: 0.05, noiseFloor: 0.02)
        for template in templates {
            for partial in template.partials {
                let key = FakeHarmonicBandEnergyProvider.key(partial.centerFrequency)
                provider.bandEnergies[key] = 4
                provider.surroundingEnergies[key] = 4
            }
        }
        let results = HarmonicTemplateScorer().score(templates: templates, energyProvider: provider, profile: profile)
        #expect(results.allSatisfy { $0.confidence < profile.minimumConfidence })
    }
}
