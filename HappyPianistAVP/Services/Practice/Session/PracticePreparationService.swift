import CryptoKit
import Foundation

enum PracticePreparationError: Error, Equatable, Sendable {
    case scoreFileNotFound
    case scoreFileUnreadable(reason: String)
    case invalidMXLArchive
    case missingMXLContainer
    case missingMXLRootfile
    case missingMXLScore(path: String)
    case invalidMXLContainer
    case xmlParseFailed(line: Int?, column: Int?, reason: String)
    case unsupportedRootElement(reason: String)
    case noPlayableNotes
    case missingMeasureStructure
    case unexpected(stage: String, reason: String)
}


enum PracticePreparationErrorDetails {
    static func safeErrorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(String(reflecting: type(of: error))) [\(nsError.domain):\(nsError.code)]"
    }

    static func safeArchiveEntry(_ path: String) -> String {
        let normalized = path.replacing("\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
        let isSafeRelativePath = normalized.hasPrefix("/") == false &&
            normalized.contains("://") == false &&
            components.allSatisfy { $0 != "." && $0 != ".." }
        if isSafeRelativePath, components.isEmpty == false {
            return components.joined(separator: "/")
        }
        let fileName = URL(fileURLWithPath: normalized).lastPathComponent
        return fileName.isEmpty ? "unknown-score.xml" : fileName
    }
}

protocol PracticePreparationServiceProtocol {
    func prepare(
        songID: UUID,
        from scoreURL: URL,
        file: ImportedMusicXMLFile
    ) async throws -> PreparedPractice
}

actor PracticePreparationService: PracticePreparationServiceProtocol {
    private let parser: MusicXMLParserProtocol
    private let stepBuilder: PracticeStepBuilderProtocol
    private let structureExpander = MusicXMLStructureExpander()

    init(
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil
    ) {
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
    }

    func prepare(
        songID: UUID,
        from scoreURL: URL,
        file: ImportedMusicXMLFile
    ) async throws -> PreparedPractice {
        try Task.checkCancellation()
        let scoreBytes: Data
        do {
            scoreBytes = try Data(contentsOf: scoreURL)
        } catch {
            throw Self.fileAccessError(from: error)
        }
        let revision = SHA256.hash(data: scoreBytes).map(Self.hexByte).joined()

        try Task.checkCancellation()
        let rawScore: MusicXMLScore
        do {
            rawScore = try parser.parse(fileURL: scoreURL)
        } catch let error as MXLReaderError {
            throw Self.mapMXLReaderError(error)
        } catch let error as MusicXMLParserError {
            switch error {
            case let .parseFailed(line, column, reason):
                throw PracticePreparationError.xmlParseFailed(
                    line: line,
                    column: column,
                    reason: reason
                )
            }
        } catch MusicXMLTimewiseConverterError.invalidXML {
            throw PracticePreparationError.xmlParseFailed(
                line: nil,
                column: nil,
                reason: "The MusicXML document is not valid XML."
            )
        } catch MusicXMLTimewiseConverterError.unsupportedRootElement {
            throw PracticePreparationError.unsupportedRootElement(
                reason: "Expected score-partwise or score-timewise as the root element."
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PracticePreparationError.unexpected(
                stage: "musicXMLParsing",
                reason: PracticePreparationErrorDetails.safeErrorSummary(error)
            )
        }
        let score = MusicXMLPianoGrandStaffNormalizer().normalize(score: rawScore)
        let shouldExpandStructure = MusicXMLRealisticPlaybackDefaults.shouldExpandStructure
        let primaryPartIDForExpansion = score.preferredPrimaryPartID()

        try Task.checkCancellation()
        let effectiveScore = shouldExpandStructure
            ? structureExpander.expandStructureIfPossible(score: score, primaryPartID: primaryPartIDForExpansion)
            : score
        let primaryPartID = effectiveScore.preferredPrimaryPartID(preferredPartID: primaryPartIDForExpansion)
        let practiceScore = effectiveScore.filtering(toPartID: primaryPartID)
        let routedPracticeScore = MusicXMLHandRouter().routeIfNeeded(score: practiceScore)

        try Task.checkCancellation()
        let expressivityOptions = MusicXMLRealisticPlaybackDefaults.expressivityOptions
        let buildResult = stepBuilder.buildSteps(from: routedPracticeScore, expressivity: expressivityOptions)
        let wordsSemantics = expressivityOptions.wordsSemanticsEnabled
            ? MusicXMLWordsSemanticsInterpreter().interpret(
                wordsEvents: routedPracticeScore.wordsEvents,
                tempoEvents: routedPracticeScore.tempoEvents
            )
            : nil
        let tempoMap = MusicXMLTempoMap(
            tempoEvents: routedPracticeScore.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
            tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
            partID: primaryPartID
        )
        let pedalTimeline = MusicXMLPedalTimeline(events: routedPracticeScore
            .pedalEvents + (wordsSemantics?.derivedPedalEvents ?? []))
        let fermataTimeline = expressivityOptions.fermataEnabled
            ? MusicXMLFermataTimeline(
                fermataEvents: routedPracticeScore.fermataEvents,
                notes: routedPracticeScore.notes
            )
            : nil
        let attributeTimeline = MusicXMLAttributeTimeline(
            timeSignatureEvents: routedPracticeScore.timeSignatureEvents,
            keySignatureEvents: routedPracticeScore.keySignatureEvents,
            clefEvents: routedPracticeScore.clefEvents
        )
        let slurTimeline = MusicXMLSlurTimeline(events: routedPracticeScore.slurEvents)
        let noteSpans = MusicXMLNoteSpanBuilder().buildSpans(
            from: routedPracticeScore.notes,
            performanceTimingEnabled: MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled,
            expressivity: expressivityOptions,
            fermataTimeline: fermataTimeline
        )
        let highlightGuides = PianoHighlightGuideBuilderService().buildGuides(
            input: PianoHighlightGuideBuildInput(
                score: routedPracticeScore,
                steps: buildResult.steps,
                noteSpans: noteSpans,
                expressivity: expressivityOptions
            )
        )

        try Task.checkCancellation()
        guard buildResult.steps.isEmpty == false else {
            throw PracticePreparationError.noPlayableNotes
        }
        guard routedPracticeScore.measures.isEmpty == false else {
            throw PracticePreparationError.missingMeasureStructure
        }
        return PreparedPractice(
            identity: PracticeSongIdentity(songID: songID, scoreRevision: revision),
            steps: buildResult.steps,
            file: file,
            tempoMap: tempoMap,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            attributeTimeline: attributeTimeline,
            slurTimeline: slurTimeline,
            highlightGuides: highlightGuides,
            measureSpans: routedPracticeScore.measures,
            unsupportedNoteCount: buildResult.unsupportedNoteCount
        )
    }

    private static func fileAccessError(from error: Error) -> PracticePreparationError {
        let cocoaError = error as? CocoaError
        if cocoaError?.code == .fileNoSuchFile || cocoaError?.code == .fileReadNoSuchFile {
            return .scoreFileNotFound
        }
        return .scoreFileUnreadable(reason: PracticePreparationErrorDetails.safeErrorSummary(error))
    }

    private static func mapMXLReaderError(_ error: MXLReaderError) -> PracticePreparationError {
        switch error {
        case .invalidArchive:
            .invalidMXLArchive
        case .missingContainerXML:
            .missingMXLContainer
        case .missingRootfileFullPath:
            .missingMXLRootfile
        case let .missingScoreXML(path):
            .missingMXLScore(path: PracticePreparationErrorDetails.safeArchiveEntry(path))
        case .invalidContainerXML:
            .invalidMXLContainer
        }
    }

    private static func hexByte(_ byte: UInt8) -> String {
        let value = String(byte, radix: 16)
        return value.count == 1 ? "0" + value : value
    }
}
