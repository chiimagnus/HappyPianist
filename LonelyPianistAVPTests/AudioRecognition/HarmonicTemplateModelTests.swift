@testable import LonelyPianistAVP
import Testing

struct HarmonicTemplateModelTests {
    @Test func defaultProfilesContainValidPartials() {
        let profile = HarmonicTemplateTuningProfile.lowLatencyDefault
        #expect(profile.harmonicIndices == [1, 2, 3, 4, 5])
        #expect(profile.weight(for: 1) > profile.weight(for: 5))
        #expect(profile.toleranceCents(for: 1) > 0)
        #expect(HarmonicTemplateCandidateRole.expected.priority > HarmonicTemplateCandidateRole.wrongCandidate.priority)
    }
}
