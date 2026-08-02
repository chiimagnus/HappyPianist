import Foundation

public enum PerformanceTargetProvenance: String, Equatable, Hashable, Sendable {
    case scoreDefault
    case teacher
    case userConfirmed
    case genericApproximation
}

public struct PerformanceTargetBand: Equatable, Hashable, Sendable {
    public let dimension: PerformanceAssessmentDimension
    public let lowerBound: Double
    public let upperBound: Double
    public let provenance: PerformanceTargetProvenance
    public let sourceID: String?

    public init?(
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

    public func contains(_ value: Double) -> Bool {
        value.isFinite && lowerBound ... upperBound ~= value
    }

    public func widened(by factor: Double) -> Self {
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

public struct PerformanceTargetProfile: Equatable, Sendable {
    public let bands: [PerformanceTargetBand]

    public init(bands: [PerformanceTargetBand] = []) {
        self.bands = bands
    }

    public func bands(for dimension: PerformanceAssessmentDimension) -> [PerformanceTargetBand] {
        bands.filter { $0.dimension == dimension }
    }
}
