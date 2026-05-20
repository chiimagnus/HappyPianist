import Foundation

struct HarmonicTemplateProvider: Sendable {
    func makeTemplates(
        expectedMIDINotes: [Int],
        wrongCandidateMIDINotes: [Int],
        profile: HarmonicTemplateTuningProfile
    ) -> [HarmonicTemplate] {
        var rolesByNote: [Int: HarmonicTemplateCandidateRole] = [:]
        for note in expectedMIDINotes {
            rolesByNote[note] = .expected
        }
        for note in wrongCandidateMIDINotes
            where rolesByNote[note] == nil || rolesByNote[note]!.priority < HarmonicTemplateCandidateRole.wrongCandidate
            .priority
        {
            rolesByNote[note] = .wrongCandidate
        }
        for note in expectedMIDINotes {
            for octaveNote in [note - 12, note + 12] where (21 ... 108).contains(octaveNote) {
                if rolesByNote[octaveNote] == nil {
                    rolesByNote[octaveNote] = .octaveDebug
                }
            }
        }

        return rolesByNote
            .map { midiNote, role in
                HarmonicTemplate(
                    midiNote: midiNote,
                    role: role,
                    partials: makePartials(midiNote: midiNote, profile: profile)
                )
            }
            .sorted { lhs, rhs in
                if lhs.role.priority != rhs.role.priority { return lhs.role.priority > rhs.role.priority }
                return lhs.midiNote < rhs.midiNote
            }
    }

    func midiFrequency(midiNote: Int) -> Double {
        440.0 * pow(2.0, Double(midiNote - 69) / 12.0)
    }

    private func makePartials(midiNote: Int, profile: HarmonicTemplateTuningProfile) -> [HarmonicPartialTemplate] {
        let baseFrequency = midiFrequency(midiNote: midiNote)
        return profile.harmonicIndices.map { harmonicIndex in
            HarmonicPartialTemplate(
                harmonicIndex: harmonicIndex,
                centerFrequency: baseFrequency * Double(harmonicIndex),
                toleranceCents: profile.toleranceCents(for: harmonicIndex),
                weight: profile.weight(for: harmonicIndex)
            )
        }
    }
}
