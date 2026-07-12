import Foundation

enum LibraryPracticePreparationState: Equatable, Sendable {
    case idle
    case loading(entryID: UUID)
    case ready(entryID: UUID, identity: PracticeSongIdentity)
    case failure(LibraryPracticePreparationFailure)
}

struct LibraryPracticePreparationFailure: Equatable, Identifiable, Sendable {
    let id: UUID
    let entryID: UUID
    let code: DiagnosticCode
    let title: String
    let explanation: String
    let stage: String
    let file: DiagnosticFileReference?
    let sourceLocation: DiagnosticSourceLocation?
    let reason: String

    init(
        id: UUID = UUID(),
        entryID: UUID,
        code: DiagnosticCode,
        title: String,
        explanation: String,
        stage: String,
        file: DiagnosticFileReference?,
        sourceLocation: DiagnosticSourceLocation? = nil,
        reason: String
    ) {
        self.id = id
        self.entryID = entryID
        self.code = code
        self.title = title
        self.explanation = explanation
        self.stage = stage
        self.file = file
        self.sourceLocation = sourceLocation
        self.reason = reason
    }

    var technicalDetails: String {
        DiagnosticEvent(
            severity: .error,
            code: code,
            category: .practicePreparation,
            stage: stage,
            summary: title,
            reason: reason,
            songID: entryID,
            file: file,
            sourceLocation: sourceLocation,
            persistence: .exportable
        ).textRepresentation
    }

    var diagnosticEvent: DiagnosticEvent {
        DiagnosticEvent(
            severity: .error,
            code: code,
            category: .practicePreparation,
            stage: stage,
            summary: title,
            reason: reason,
            songID: entryID,
            file: file,
            sourceLocation: sourceLocation,
            persistence: .exportable
        )
    }

    static func map(
        _ error: PracticePreparationError,
        entryID: UUID,
        file: DiagnosticFileReference?
    ) -> LibraryPracticePreparationFailure {
        switch error {
        case .scoreFileNotFound:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceScoreFileNotFound,
                title: "找不到曲谱文件",
                explanation: "原始曲谱文件已被移动或删除，请重新导入这份曲谱。",
                stage: "scoreFileAccess",
                file: file,
                reason: "The score file does not exist at the application-relative location."
            )
        case let .scoreFileUnreadable(reason):
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceScoreFileUnreadable,
                title: "无法读取曲谱文件",
                explanation: "应用无法读取这份曲谱，请检查文件后重新导入。",
                stage: "scoreFileAccess",
                file: file,
                reason: reason
            )
        case .invalidMXLArchive:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceMXLInvalidArchive,
                title: "压缩曲谱已损坏",
                explanation: "这份 .mxl 文件不是有效的压缩 MusicXML，请重新导出或重新导入。",
                stage: "mxlArchive",
                file: file,
                reason: "ZIPFoundation could not open the MXL archive."
            )
        case .missingMXLContainer:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceMXLMissingContainer,
                title: "压缩曲谱缺少入口文件",
                explanation: "这份 .mxl 文件中缺少 META-INF/container.xml。",
                stage: "mxlContainer",
                file: file,
                reason: "META-INF/container.xml is missing."
            )
        case .missingMXLRootfile:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceMXLMissingRootfile,
                title: "压缩曲谱没有指定主曲谱",
                explanation: "container.xml 中没有可用的主 MusicXML 路径。",
                stage: "mxlContainer",
                file: file,
                reason: "container.xml does not contain a rootfile full-path."
            )
        case let .missingMXLScore(path):
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceMXLMissingScore,
                title: "压缩曲谱中找不到主曲谱",
                explanation: "压缩包指定的主 MusicXML 文件不存在。",
                stage: "mxlScoreExtraction",
                file: file,
                reason: "The rootfile entry is missing: \(path)"
            )
        case .invalidMXLContainer:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceMXLInvalidContainer,
                title: "压缩曲谱入口文件无效",
                explanation: "META-INF/container.xml 不是有效的 XML。",
                stage: "mxlContainer",
                file: file,
                reason: "The MXL container document could not be parsed."
            )
        case let .xmlParseFailed(line, column, reason):
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceXMLParseFailed,
                title: "无法解析 MusicXML",
                explanation: "曲谱包含无效或不完整的 XML 内容，请修复文件后重新导入。",
                stage: "musicXMLParsing",
                file: file,
                sourceLocation: DiagnosticSourceLocation(line: line, column: column),
                reason: reason
            )
        case let .unsupportedRootElement(reason):
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practicePreparationFailed,
                title: "不支持这份 MusicXML 结构",
                explanation: "曲谱根元素不是当前支持的 score-partwise 或 score-timewise。",
                stage: "musicXMLNormalization",
                file: file,
                reason: reason
            )
        case .noPlayableNotes:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceNoPlayableNotes,
                title: "曲谱中没有可练习的音符",
                explanation: "解析完成，但没有找到可以生成练习步骤的音符。",
                stage: "practiceStepBuilding",
                file: file,
                reason: "The prepared score produced zero practice steps."
            )
        case .missingMeasureStructure:
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practiceMissingMeasureStructure,
                title: "曲谱的小节结构不完整",
                explanation: "曲谱已生成练习音符，但缺少对应的小节时间范围。",
                stage: "practiceValidation",
                file: file,
                reason: "Practice steps exist but measure spans are empty."
            )
        case let .unexpected(stage, reason):
            LibraryPracticePreparationFailure(
                entryID: entryID,
                code: .practicePreparationFailed,
                title: "无法准备这份曲谱",
                explanation: "准备练习数据时发生未预期的错误。",
                stage: stage,
                file: file,
                reason: reason
            )
        }
    }
}

struct LibraryPracticePanelPresentation: Equatable {
    let entryID: UUID
    let identity: PracticeSongIdentity
    let measureMap: PracticeMeasureMapViewModel
    let stableMeasureCount: Int
    let totalMeasureCount: Int
    let hotspotTitle: String?
    let resumeText: String
    let launchSummary: String
    let passageTitle: String
    let hasSavedProgress: Bool

    init?(
        entryID: UUID,
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

        self.entryID = entryID
        self.identity = identity
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
        passageTitle = resolvedPassageTitle
        hasSavedProgress = exactProgress?.resumePoint != nil
    }
}
