import Foundation

enum LibraryPracticePreparationState: Equatable, Sendable {
    case idle
    case loading(entryID: UUID)
    case ready(entryID: UUID, identity: PracticeSongIdentity)
    case failure(PracticeLaunchFailure)
}
struct LibraryPracticeMeasureOption: Equatable, Identifiable, Sendable {
    let id: PracticeMeasureOccurrenceID
    let title: String
    let occurrenceIndex: Int

    static func make(from measureSpans: [MusicXMLMeasureSpan]) -> [LibraryPracticeMeasureOption] {
        let occurrenceTotals = Dictionary(grouping: measureSpans, by: \.sourceMeasureID)
            .mapValues(\.count)
        var occurrenceCounts: [PracticeSourceMeasureID: Int] = [:]

        return measureSpans.map { span in
            let occurrenceNumber = occurrenceCounts[span.sourceMeasureID, default: 0] + 1
            occurrenceCounts[span.sourceMeasureID] = occurrenceNumber
            let measureTitle = PracticePassagePresentation.measureTitle(span.sourceMeasureID)
            let title = occurrenceTotals[span.sourceMeasureID, default: 0] > 1
                ? "第 \(measureTitle) 小节 · 第 \(occurrenceNumber) 次"
                : "第 \(measureTitle) 小节"
            return LibraryPracticeMeasureOption(
                id: span.occurrenceID,
                title: title,
                occurrenceIndex: span.occurrenceIndex
            )
        }
    }
}

struct LibraryPracticePanelPresentation: Equatable {
    let measureMap: PracticeMeasureMapViewModel
    let stableMeasureCount: Int
    let totalMeasureCount: Int
    let hotspotTitle: String?
    let resumeText: String
    let launchSummary: String

    init?(
        identity: PracticeSongIdentity,
        measureSpans: [MusicXMLMeasureSpan],
        progress: SongPracticeProgress?,
        configuration: PracticeRoundConfiguration,
        currentMeasure: PracticeSourceMeasureID?
    ) {
        guard measureSpans.isEmpty == false else { return nil }
        let exactProgress = progress?.identity == identity ? progress : nil
        let passageSpans = measureSpans.filter {
            configuration.passage.start.occurrenceIndex <= $0.occurrenceIndex &&
                $0.occurrenceIndex <= configuration.passage.end.occurrenceIndex
        }
        guard passageSpans.isEmpty == false else { return nil }

        let passageOccurrences = passageSpans.map(\.occurrenceID)
        let scoreSourceMeasureIDs = Set(measureSpans.map(\.sourceMeasureID))
        let passageSourceMeasureIDs = Set(passageOccurrences.map(\.sourceMeasureID))
        let allFacts = exactProgress?.measureFacts.filter {
            $0.handMode == configuration.handMode && scoreSourceMeasureIDs.contains($0.sourceMeasureID)
        } ?? []
        let passageFacts = allFacts.filter { passageSourceMeasureIDs.contains($0.sourceMeasureID) }
        let stableSourceMeasureIDs = Set(
            allFacts.lazy.filter { $0.state == .stable }.map(\.sourceMeasureID)
        )
        let hotspot = PracticeHotspotPolicy().hotspot(in: passageFacts)
        let isFullScore = configuration.passage.start == measureSpans.first?.occurrenceID &&
            configuration.passage.end == measureSpans.last?.occurrenceID
        let resolvedPassageTitle = isFullScore
            ? "整首"
            : PracticePassagePresentation.title(for: passageOccurrences)
        let tempoTitle = configuration.tempoScale.formatted(
            .percent.precision(.fractionLength(0))
        )
        let savedResumePoint = exactProgress.flatMap { progress -> PracticeResumePoint? in
            guard progress.activeConfiguration == configuration,
                  let resumePoint = progress.resumePoint,
                  configuration.passage.start.occurrenceIndex <= resumePoint.occurrenceID.occurrenceIndex,
                  resumePoint.occurrenceID.occurrenceIndex <= configuration.passage.end.occurrenceIndex
            else { return nil }
            return resumePoint
        }

        measureMap = PracticeMeasureMapViewModel(
            measureSpans: measureSpans,
            progress: exactProgress,
            handMode: configuration.handMode,
            currentPassage: configuration.passage,
            currentMeasure: currentMeasure
        )
        stableMeasureCount = stableSourceMeasureIDs.count
        totalMeasureCount = scoreSourceMeasureIDs.count
        hotspotTitle = hotspot.map {
            "第 \(PracticePassagePresentation.measureTitle($0.sourceMeasureID)) 小节"
        }
        resumeText = savedResumePoint.map {
            "将从第 \(PracticePassagePresentation.measureTitle($0.occurrenceID.sourceMeasureID)) 小节继续"
        } ?? (exactProgress == nil ? "尚无练习记录" : "将从所选片段开始")
        launchSummary = "\(resolvedPassageTitle) · \(configuration.handMode.title) · \(tempoTitle)"
    }
}
