import Foundation

enum HarmonicTemplateCandidateRole: String, Equatable, CaseIterable, Sendable {
    case expected
    case wrongCandidate
    case octaveDebug

    var priority: Int {
        switch self {
            case .expected: 3
            case .wrongCandidate: 2
            case .octaveDebug: 1
        }
    }
}

struct HarmonicPartialTemplate: Equatable, Sendable {
    let harmonicIndex: Int
    let centerFrequency: Double
    let toleranceCents: Double
    let weight: Double
}

struct HarmonicTemplate: Equatable, Sendable {
    let midiNote: Int
    let role: HarmonicTemplateCandidateRole
    let partials: [HarmonicPartialTemplate]
}

struct HarmonicPartialDebugValue: Equatable, Sendable {
    let harmonicIndex: Int
    let centerFrequency: Double
    let bandEnergy: Double
    let surroundingEnergy: Double
    let weightedEnergy: Double
}
