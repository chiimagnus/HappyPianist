import Foundation

struct HarmonicTemplateScorer: Sendable {
    private let epsilon = 1e-9

    func score(
        templates: [HarmonicTemplate],
        energyProvider: any HarmonicBandEnergyProviding,
        profile: HarmonicTemplateTuningProfile
    ) -> [TemplateMatchResult] {
        let partialSummaries = templates.map { template in
            let partials = template.partials.map { partial in
                let band = energyProvider.bandEnergy(
                    centerFrequency: partial.centerFrequency,
                    toleranceCents: partial.toleranceCents
                )
                let surrounding = energyProvider.surroundingEnergy(
                    centerFrequency: partial.centerFrequency,
                    toleranceCents: partial.toleranceCents
                )
                return HarmonicPartialDebugValue(
                    harmonicIndex: partial.harmonicIndex,
                    centerFrequency: partial.centerFrequency,
                    bandEnergy: band,
                    surroundingEnergy: surrounding,
                    weightedEnergy: band * partial.weight
                )
            }
            let harmonicScore = partials.reduce(0.0) { $0 + $1.weightedEnergy }
            let harmonicBandEnergy = partials.reduce(0.0) { $0 + $1.bandEnergy }
            let surroundingEnergy = partials.reduce(0.0) { $0 + $1.surroundingEnergy }
            let tonalRatio = harmonicBandEnergy / max(surroundingEnergy, epsilon)
            let activePartialCount = partials.filter { partial in
                partial.bandEnergy > max(partial.surroundingEnergy * profile.minimumTonalRatio, epsilon)
            }.count
            return (template: template, partials: partials, harmonicScore: harmonicScore, tonalRatio: tonalRatio, activePartialCount: activePartialCount)
        }

        let maxWrongScore = partialSummaries
            .filter { $0.template.role == .wrongCandidate }
            .map(\.harmonicScore)
            .max() ?? 0
        let maxExpectedScore = partialSummaries
            .filter { $0.template.role == .expected }
            .map(\.harmonicScore)
            .max() ?? 0
        let globalMax = max(partialSummaries.map(\.harmonicScore).max() ?? 0, epsilon)

        return partialSummaries.map { summary in
            let dominance: Double
            switch summary.template.role {
                case .expected:
                    dominance = summary.harmonicScore / max(maxWrongScore, epsilon)
                case .wrongCandidate:
                    dominance = summary.harmonicScore / max(maxExpectedScore, epsilon)
                case .octaveDebug:
                    dominance = summary.harmonicScore / globalMax
            }
            let normalizedHarmonic = min(1.0, summary.harmonicScore / globalMax)
            let tonalFactor = min(1.0, summary.tonalRatio / max(profile.minimumTonalRatio, epsilon))
            let dominanceFactor = min(1.0, dominance / max(profile.minimumDominance, epsilon))
            let requiredActivePartials = min(2, max(1, summary.template.partials.count))
            let completenessFactor = min(1.0, Double(summary.activePartialCount) / Double(requiredActivePartials))
            let noiseGateFactor = min(1.0, energyProvider.rms / max(profile.minimumRMS, epsilon))
            let roleFactor = summary.template.role == .octaveDebug ? 0.75 : 1.0
            let confidence = max(0, min(1.0, normalizedHarmonic * tonalFactor * dominanceFactor * completenessFactor * noiseGateFactor * roleFactor))
            return TemplateMatchResult(
                midiNote: summary.template.midiNote,
                role: summary.template.role,
                confidence: confidence,
                harmonicScore: summary.harmonicScore,
                tonalRatio: summary.tonalRatio,
                dominanceOverWrong: dominance,
                strongestPartials: summary.partials.sorted { $0.weightedEnergy > $1.weightedEnergy }.prefix(5).map { $0 }
            )
        }
        .sorted { lhs, rhs in
            if lhs.role.priority != rhs.role.priority { return lhs.role.priority > rhs.role.priority }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.midiNote < rhs.midiNote
        }
    }
}
