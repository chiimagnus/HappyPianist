import Foundation


public enum MusicXMLGlissandoPitchPolicy: String, Codable, Equatable, Sendable {
    case chromatic
}

public struct MusicXMLInterpretationProfile: Equatable, Sendable {
    public static let generic = MusicXMLInterpretationProfile(
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

    public let id: String
    public let staccatissimoDurationMultiplier: Double
    public let staccatoDurationMultiplier: Double
    public let tenutoDurationMultiplier: Double
    public let detachedLegatoDurationMultiplier: Double
    public let marcatoDurationMultiplier: Double
    public let breathGapTicks: Int
    public let caesuraPauseTicks: Int
    public let ornamentSubdivisionTicks: Int
    public let unmeasuredTremoloSubdivisionTicks: Int
    public let glissandoPitchPolicy: MusicXMLGlissandoPitchPolicy
    public let fermataExtraDurationMultiplier: Double
    public let fermataMaximumExtraTicks: Int

    public func durationMultiplier(for articulations: Set<MusicXMLArticulation>) -> Double {
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

    public func hasDurationRule(for articulations: Set<MusicXMLArticulation>) -> Bool {
        articulations.isDisjoint(with: [
            .staccatissimo,
            .staccato,
            .tenuto,
            .detachedLegato,
            .marcato,
        ]) == false
    }

    public func fermataExtraTicks(forBaseDurationTicks durationTicks: Int) -> Int {
        let base = max(1, durationTicks)
        let proposed = max(1, Int((Double(base) * fermataExtraDurationMultiplier).rounded()))
        return min(proposed, max(1, fermataMaximumExtraTicks))
    }
}
