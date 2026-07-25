import Foundation

enum MusicXMLGlissandoPitchPolicy: String, Codable, Equatable {
    case chromatic
}

struct MusicXMLInterpretationProfile: Equatable {
    static let generic = MusicXMLInterpretationProfile(
        id: "generic-score-v1",
        staccatissimoDurationMultiplier: 0.25,
        staccatoDurationMultiplier: 0.5,
        tenutoDurationMultiplier: 1,
        detachedLegatoDurationMultiplier: 0.75,
        marcatoDurationMultiplier: 0.75,
        breathGapTicks: MusicXMLTempoMap.ticksPerQuarter / 8,
        caesuraPauseTicks: MusicXMLTempoMap.ticksPerQuarter / 2,
        ornamentSubdivisionTicks: MusicXMLTempoMap.ticksPerQuarter / 8,
        unmeasuredTremoloSubdivisionTicks: MusicXMLTempoMap.ticksPerQuarter / 8,
        glissandoPitchPolicy: .chromatic,
        fermataExtraDurationMultiplier: 0.5,
        fermataMaximumExtraTicks: MusicXMLTempoMap.ticksPerQuarter * 2
    )

    let id: String
    let staccatissimoDurationMultiplier: Double
    let staccatoDurationMultiplier: Double
    let tenutoDurationMultiplier: Double
    let detachedLegatoDurationMultiplier: Double
    let marcatoDurationMultiplier: Double
    let breathGapTicks: Int
    let caesuraPauseTicks: Int
    let ornamentSubdivisionTicks: Int
    let unmeasuredTremoloSubdivisionTicks: Int
    let glissandoPitchPolicy: MusicXMLGlissandoPitchPolicy
    let fermataExtraDurationMultiplier: Double
    let fermataMaximumExtraTicks: Int

    func durationMultiplier(for articulations: Set<MusicXMLArticulation>) -> Double {
        if articulations.contains(.staccatissimo) {
            return staccatissimoDurationMultiplier
        }
        if articulations.contains(.staccato) {
            return staccatoDurationMultiplier
        }
        if articulations.contains(.tenuto) {
            return tenutoDurationMultiplier
        }
        if articulations.contains(.detachedLegato) {
            return detachedLegatoDurationMultiplier
        }
        if articulations.contains(.marcato) {
            return marcatoDurationMultiplier
        }
        return 1
    }

    func hasDurationRule(for articulations: Set<MusicXMLArticulation>) -> Bool {
        articulations.isDisjoint(with: [
            .staccatissimo,
            .staccato,
            .tenuto,
            .detachedLegato,
            .marcato,
        ]) == false
    }

    func fermataExtraTicks(forBaseDurationTicks durationTicks: Int) -> Int {
        let base = max(1, durationTicks)
        let proposed = max(1, Int((Double(base) * fermataExtraDurationMultiplier).rounded()))
        return min(proposed, max(1, fermataMaximumExtraTicks))
    }
}
