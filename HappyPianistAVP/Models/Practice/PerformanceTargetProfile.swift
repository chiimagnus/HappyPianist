import Foundation

enum PerformanceTargetProvenance: String, Equatable, Hashable, Sendable {
    case scoreDefault
    case teacher
    case userConfirmed
    case genericApproximation
}

struct PerformanceTargetBand: Equatable, Hashable, Sendable {
    let dimension: PerformanceAssessmentDimension
    let lowerBound: Double
    let upperBound: Double
    let provenance: PerformanceTargetProvenance
    let sourceID: String?

    init?(
        dimension: PerformanceAssessmentDimension,
        lowerBound: Double,
        upperBound: Double,
        provenance: PerformanceTargetProvenance,
        sourceID: String? = nil
    ) {
        guard lowerBound.isFinite, upperBound.isFinite, lowerBound <= upperBound else { return nil }
        self.dimension = dimension
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.provenance = provenance
        self.sourceID = sourceID
    }

    func contains(_ value: Double) -> Bool {
        value.isFinite && lowerBound ... upperBound ~= value
    }

    func widened(by factor: Double) -> Self {
        guard factor.isFinite, factor >= 1 else { return self }
        let center = (lowerBound / 2) + (upperBound / 2)
        let halfWidth = ((upperBound / 2) - (lowerBound / 2)) * factor
        return Self(
            dimension: dimension,
            lowerBound: center - halfWidth,
            upperBound: center + halfWidth,
            provenance: provenance,
            sourceID: sourceID
        ) ?? self
    }
}

struct PerformanceTargetProfile: Equatable, Sendable {
    let bands: [PerformanceTargetBand]

    init(bands: [PerformanceTargetBand] = []) {
        self.bands = bands
    }

    func bands(for dimension: PerformanceAssessmentDimension) -> [PerformanceTargetBand] {
        bands.filter { $0.dimension == dimension }
    }
}
