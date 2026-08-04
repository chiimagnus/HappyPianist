import Foundation

public struct PracticeExactProgressRestoration: Equatable, Sendable {
    public let progress: SongPracticeProgress
    public let activeRange: PracticeActiveRange?
    public let activeRangeDiagnostic: PracticeMeasureIndexDiagnostic?
    public let didRepairSavedState: Bool
}

public enum PracticeExactProgressRestorer {
    public static func restore(
        _ savedProgress: SongPracticeProgress,
        freshConfiguration: PracticeRoundConfiguration?,
        measureIndex: PracticeMeasureIndex?
    ) -> PracticeExactProgressRestoration {
        var progress = savedProgress
        var didRepairSavedState = false

        if progress.activeConfiguration == nil, progress.resumePoint != nil {
            progress.activeConfiguration = freshConfiguration
            progress.resumePoint = nil
            didRepairSavedState = true
        }

        guard let measureIndex else {
            if savedProgress.activeConfiguration != nil {
                progress.activeConfiguration = freshConfiguration
                progress.resumePoint = nil
                didRepairSavedState = true
            }

            return PracticeExactProgressRestoration(
                progress: progress,
                activeRange: nil,
                activeRangeDiagnostic: nil,
                didRepairSavedState: didRepairSavedState
            )
        }

        var range = resolveActiveRange(for: progress.activeConfiguration, measureIndex: measureIndex)
        if progress.activeConfiguration != nil, range.activeRange == nil {
            progress.activeConfiguration = freshConfiguration
            progress.resumePoint = nil
            didRepairSavedState = true
            range = resolveActiveRange(for: freshConfiguration, measureIndex: measureIndex)
        }

        if let resumePoint = progress.resumePoint,
           isValid(resumePoint, in: range.activeRange, measureIndex: measureIndex) == false
        {
            progress.resumePoint = nil
            didRepairSavedState = true
        }

        return PracticeExactProgressRestoration(
            progress: progress,
            activeRange: range.activeRange,
            activeRangeDiagnostic: range.diagnostic,
            didRepairSavedState: didRepairSavedState
        )
    }

    private static func resolveActiveRange(
        for configuration: PracticeRoundConfiguration?,
        measureIndex: PracticeMeasureIndex
    ) -> (activeRange: PracticeActiveRange?, diagnostic: PracticeMeasureIndexDiagnostic?) {
        guard let configuration else {
            return (nil, nil)
        }

        do {
            return (try measureIndex.resolve(configuration.passage), nil)
        } catch let diagnostic as PracticeMeasureIndexDiagnostic {
            return (nil, diagnostic)
        } catch {
            return (nil, .passageBoundaryNotFound)
        }
    }

    private static func isValid(
        _ resumePoint: PracticeResumePoint,
        in activeRange: PracticeActiveRange?,
        measureIndex: PracticeMeasureIndex
    ) -> Bool {
        measureIndex.occurrenceID(forStepIndex: resumePoint.stepIndex) == resumePoint.occurrenceID &&
            (activeRange?.contains(stepIndex: resumePoint.stepIndex) ?? true)
    }
}
