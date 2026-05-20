@testable import LonelyPianistAVP
import Testing

struct HarmonicTemplateProviderTests {
    @Test func sessionBuilderBuildsExpectedWrongAndOctaveTemplates() {
        let templates = HarmonicTemplateProvider().makeTemplates(
            expectedMIDINotes: [60, 64, 67],
            wrongCandidateMIDINotes: [59, 61, 64],
            profile: .lowLatencyDefault
        )
        #expect(templates.contains { $0.midiNote == 60 && $0.role == .expected })
        #expect(templates.contains { $0.midiNote == 59 && $0.role == .wrongCandidate })
        #expect(templates.contains { $0.midiNote == 48 && $0.role == .octaveDebug })
        #expect(templates.first { $0.midiNote == 64 }?.role == .expected)
        #expect(templates.allSatisfy { $0.partials.count == 5 })
    }
}
