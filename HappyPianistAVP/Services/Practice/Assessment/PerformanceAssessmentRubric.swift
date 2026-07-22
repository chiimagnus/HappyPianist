import Foundation

struct PerformanceAssessmentRubric: Sendable {
    let version = PerformanceAssessmentRubricVersion.capabilityAware
    private let targetProfile: PerformanceTargetProfile

    init(targetProfile: PerformanceTargetProfile = PerformanceTargetProfile()) {
        self.targetProfile = targetProfile
    }

    func acceptableBands(
        for dimension: PerformanceAssessmentDimension,
        capabilities: PerformanceInputCapabilities
    ) -> [PerformanceTargetBand] {
        acceptableBands(
            for: dimension,
            evidenceStatus: evidence(for: dimension, capabilities: capabilities) == .degraded
                ? .degraded
                : .observed
        )
    }

    func acceptableBands(
        for dimension: PerformanceAssessmentDimension,
        evidenceStatus: PerformanceAssessmentEvidenceStatus
    ) -> [PerformanceTargetBand] {
        let configured = targetProfile.bands(for: dimension)
        let isDegraded = evidenceStatus == .degraded
        guard configured.isEmpty == false else {
            return [Self.genericBand(for: dimension, scale: isDegraded ? 1.5 : 1)]
        }
        return isDegraded ? configured.map { $0.widened(by: 1.5) } : configured
    }

    func accepts(
        _ value: Double,
        for dimension: PerformanceAssessmentDimension,
        capabilities: PerformanceInputCapabilities
    ) -> Bool {
        acceptableBands(for: dimension, capabilities: capabilities).contains { $0.contains(value) }
    }

    func accepts(
        _ value: Double,
        for dimension: PerformanceAssessmentDimension,
        evidenceStatus: PerformanceAssessmentEvidenceStatus
    ) -> Bool {
        acceptableBands(for: dimension, evidenceStatus: evidenceStatus).contains { $0.contains(value) }
    }

    func select(
        _ results: [PerformanceAssessmentDimensionResult],
        capabilities: PerformanceInputCapabilities
    ) -> [PerformanceAssessmentDimensionResult] {
        results.filter { result in
            evidence(for: result.dimension, capabilities: capabilities) != .unavailable
                && result.evidenceStatus != .notObserved
        }
    }

    func usesGenericTarget(for dimension: PerformanceAssessmentDimension) -> Bool {
        targetProfile.bands(for: dimension).isEmpty
    }

    func evidence(
        for dimension: PerformanceAssessmentDimension,
        capabilities: PerformanceInputCapabilities
    ) -> PerformanceInputCapabilities.Evidence {
        switch dimension {
        case .exactPitch, .extraNotes, .missingNotes:
            capabilities.pitch
        case .onset, .tempoRelativeTiming, .tempoContinuity, .phraseContinuity:
            capabilities.onset
        case .chordSpread:
            .required(capabilities.onset, capabilities.polyphony)
        case .duration, .release:
            capabilities.release
        case .articulation:
            .required(capabilities.onset, capabilities.release)
        case .velocity, .dynamicContour, .voicing:
            capabilities.velocity
        case .pedalTiming, .pedalValue:
            capabilities.controllers
        }
    }

    private static func genericBand(
        for dimension: PerformanceAssessmentDimension,
        scale: Double
    ) -> PerformanceTargetBand {
        let bounds: (Double, Double) = switch dimension {
        case .exactPitch: (1, 1)
        case .extraNotes, .missingNotes: (0, 0)
        case .onset: (-0.08 * scale, 0.08 * scale)
        case .tempoRelativeTiming: (-0.2 * scale, 0.2 * scale)
        case .chordSpread: (0, 0.08 * scale)
        case .duration: (1 - (0.15 * scale), 1 + (0.15 * scale))
        case .release: (-0.08 * scale, 0.08 * scale)
        case .articulation: (-0.05 * scale, 0.05 * scale)
        case .velocity: (-12 * scale, 12 * scale)
        case .dynamicContour: (-8 * scale, 8 * scale)
        case .voicing: (0, 8 * scale)
        case .pedalTiming: (-0.1 * scale, 0.1 * scale)
        case .pedalValue: (0, 0.1 * scale)
        case .tempoContinuity: (-0.25 * scale, 0.25 * scale)
        case .phraseContinuity: (-0.1 * scale, 0.1 * scale)
        }
        guard let band = PerformanceTargetBand(
            dimension: dimension,
            lowerBound: bounds.0,
            upperBound: bounds.1,
            provenance: .genericApproximation
        ) else {
            preconditionFailure("Invalid built-in performance target for \(dimension.rawValue)")
        }
        return band
    }
}

private extension PerformanceInputCapabilities.Evidence {
    static func required(_ values: Self...) -> Self {
        if values.contains(.unavailable) { return .unavailable }
        if values.contains(.degraded) { return .degraded }
        return .observed
    }
}
