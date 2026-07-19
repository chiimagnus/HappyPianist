import CryptoKit
import Foundation

enum PracticePreparationError: Error, Equatable {
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
        file: ImportedMusicXMLFile,
        options: PracticePreparationOptions
    ) async throws -> PreparedPractice
}

extension PracticePreparationServiceProtocol {
    func prepare(
        songID: UUID,
        from scoreURL: URL,
        file: ImportedMusicXMLFile
    ) async throws -> PreparedPractice {
        try await prepare(songID: songID, from: scoreURL, file: file, options: .practice)
    }
}
actor PracticePreparationService: PracticePreparationServiceProtocol {
    private let parser: MusicXMLParserProtocol
    private let stepBuilder: PracticeStepBuilderProtocol
    private let structureExpander: MusicXMLStructureExpander
    private let diagnosticsReporter: any DiagnosticsReporting

    init(
        diagnosticsReporter: any DiagnosticsReporting,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil,
        structureExpander: MusicXMLStructureExpander = MusicXMLStructureExpander()
    ) {
        self.diagnosticsReporter = diagnosticsReporter
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        self.structureExpander = structureExpander
    }

    func prepare(
        songID: UUID,
        from scoreURL: URL,
        file: ImportedMusicXMLFile,
        options: PracticePreparationOptions
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
            rawScore = if scoreURL.pathExtension.lowercased() == "mxl" {
                try parser.parse(fileURL: scoreURL)
            } else {
                try parser.parse(data: scoreBytes)
            }
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
            case let .invalidPartMetadata(reason):
                throw PracticePreparationError.xmlParseFailed(
                    line: nil,
                    column: nil,
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
        let normalizedScore = MusicXMLPianoGrandStaffNormalizer().normalize(score: rawScore)
        let selectedInstrument: MusicXMLLogicalInstrument
        switch MusicXMLPracticePartSelector().select(from: normalizedScore) {
        case let .selected(instrument):
            selectedInstrument = instrument
        case let .ambiguous(ambiguity):
            throw PracticePreparationError.unexpected(
                stage: "musicXMLPartSelection",
                reason: "Ambiguous logical instruments: \(ambiguity.candidateInstrumentIDs.joined(separator: ",")); \(ambiguity.reason)"
            )
        case .unavailable:
            throw PracticePreparationError.noPlayableNotes
        }

        guard let structuralPartID = MusicXMLPracticePartSelector().structuralPartID(
            for: selectedInstrument,
            in: normalizedScore
        ) else {
            throw PracticePreparationError.noPlayableNotes
        }
        let sourceScore = normalizedScore.filtering(toLogicalInstrument: selectedInstrument)

        try Task.checkCancellation()
        let practiceScore: MusicXMLScore
        let orderSelection: MusicXMLOrderSelection
        switch options.scoreOrder {
        case .written:
            practiceScore = sourceScore
            orderSelection = MusicXMLOrderSelection(requested: .written, applied: .written)
        case .performed:
            let expansion = structureExpander.expandStructureIfPossible(
                score: sourceScore,
                primaryPartID: structuralPartID,
                includedPartIDs: Set(selectedInstrument.memberPartIDs)
            )
            practiceScore = expansion.score
            orderSelection = MusicXMLOrderSelection(
                requested: .performed,
                applied: expansion.approximationReason == nil ? .performed : .written,
                approximationReason: expansion.approximationReason
            )
        }

        let handRouting = MusicXMLHandRouter().assignments(for: practiceScore)

        try Task.checkCancellation()
        let expressivityOptions = MusicXMLRealisticPlaybackDefaults.expressivityOptions
        let wordsSemantics = expressivityOptions.wordsSemanticsEnabled
            ? MusicXMLWordsSemanticsInterpreter().interpret(
                wordsEvents: practiceScore.wordsEvents,
                tempoEvents: practiceScore.tempoEvents
            )
            : nil
        let tempoMap = MusicXMLTempoMap(
            tempoEvents: practiceScore.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
            tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
            partID: structuralPartID
        )
        let pedalTimeline = MusicXMLPedalTimeline(events: practiceScore
            .pedalEvents + (wordsSemantics?.derivedPedalEvents ?? []))
        let fermataTimeline = expressivityOptions.fermataEnabled
            ? MusicXMLFermataTimeline(
                fermataEvents: practiceScore.fermataEvents,
                notes: practiceScore.notes
            )
            : nil
        let attributeTimeline = MusicXMLAttributeTimeline(
            timeSignatureEvents: practiceScore.timeSignatureEvents,
            keySignatureEvents: practiceScore.keySignatureEvents,
            clefEvents: practiceScore.clefEvents
        )
        let timingSchedule = ScoreTimingScheduleBuilder().build(
            notes: practiceScore.notes,
            performanceTimingEnabled: MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled,
            graceEnabled: expressivityOptions.graceEnabled,
            logicalInstruments: practiceScore.logicalInstruments,
            arpeggiateEnabled: expressivityOptions.arpeggiateEnabled
        )
        let velocityResolver = MusicXMLVelocityResolver(
            dynamicEvents: practiceScore.dynamicEvents,
            wedgeEvents: practiceScore.wedgeEvents,
            wedgeEnabled: expressivityOptions.wedgeEnabled
        )
        let identity = PracticeSongIdentity(songID: songID, scoreRevision: revision)
        let planBuildClock = ContinuousClock()
        let planBuildStarted = planBuildClock.now
        let performancePlan = ScorePerformancePlanBuilder().build(
            sourceIdentity: ScorePerformanceSourceIdentity(
                songID: songID,
                scoreRevision: revision,
                logicalInstrumentID: selectedInstrument.id
            ),
            order: orderSelection,
            logicalInstrument: selectedInstrument,
            notes: practiceScore.notes,
            timingSchedule: timingSchedule,
            velocityResolver: velocityResolver,
            expressivity: expressivityOptions,
            handAssignments: handRouting.assignmentsBySourceNoteID,
            tempoMap: tempoMap,
            pedalTimeline: pedalTimeline,
            tempoAnnotations: wordsSemantics?.tempoAnnotations ?? [],
            fermataTimeline: fermataTimeline
        )
        let planBuildDuration = planBuildStarted.duration(to: planBuildClock.now)
        let buildResult = stepBuilder.buildSteps(from: performancePlan)
        let notationProjection = ScoreNotationProjection(
            plan: performancePlan,
            sourceScore: sourceScore,
            performedScore: practiceScore
        )
        let highlightGuides = PianoHighlightGuideBuilderService().buildGuides(
            input: PianoHighlightGuideBuildInput(
                plan: performancePlan,
                sourceScore: sourceScore
            )
        )

        let measureSpans = practiceScore.measures.filter { $0.partID == structuralPartID }

        try Task.checkCancellation()
        let mismatchCounts = Self.projectionMismatchCounts(
            plan: performancePlan,
            steps: buildResult.steps,
            highlightGuides: highlightGuides,
            notationProjection: notationProjection
        )
        _ = await diagnosticsReporter.record(
            PianoPerformancePlanBuildDiagnosticSample(
                songID: songID,
                scoreRevision: revision,
                durationBucket: PianoPerformanceDurationBucket(duration: planBuildDuration),
                noteEventCount: performancePlan.noteEvents.count,
                tempoEventCount: performancePlan.tempoEvents.count,
                controllerEventCount: performancePlan.controllerEvents.count,
                annotationCount: performancePlan.annotations.count,
                unsupportedNoteCount: buildResult.unsupportedNoteCount,
                approximationCount: performancePlan.approximations.count,
                stepMismatchCount: mismatchCounts.steps,
                highlightMismatchCount: mismatchCounts.highlights,
                notationMismatchCount: mismatchCounts.notation
            ).diagnosticEvent
        )
        for sample in PianoPerformanceNotationFallbackDiagnosticSample.aggregated(
            from: notationProjection.fallbacks
        ) {
            _ = await diagnosticsReporter.record(sample.diagnosticEvent)
        }
        try Task.checkCancellation()
        guard buildResult.steps.isEmpty == false else {
            throw PracticePreparationError.noPlayableNotes
        }
        guard measureSpans.isEmpty == false else {
            throw PracticePreparationError.missingMeasureStructure
        }
        return PreparedPractice(
            identity: identity,
            performancePlan: performancePlan,
            notationProjection: notationProjection,
            steps: buildResult.steps,
            file: file,
            attributeTimeline: attributeTimeline,
            highlightGuides: highlightGuides,
            measureSpans: measureSpans,
            unsupportedNoteCount: buildResult.unsupportedNoteCount,
            scoreContext: PreparedPracticeScoreContext(
                sourceScore: sourceScore,
                preparedScore: practiceScore,
                logicalInstrument: selectedInstrument,
                structuralPartID: structuralPartID,
                orderSelection: orderSelection,
                handAssignments: handRouting.assignmentsBySourceNoteID
            )
        )
    }

    private struct StepProjectionIdentity: Hashable {
        let tick: Int
        let midiNote: Int
        let staff: Int?
        let voice: Int?
    }

    private struct ProjectionMismatchCounts {
        let steps: Int
        let highlights: Int
        let notation: Int
    }

    private static func projectionMismatchCounts(
        plan: ScorePerformancePlan,
        steps: [PracticeStep],
        highlightGuides: [PianoHighlightGuide],
        notationProjection: ScoreNotationProjection
    ) -> ProjectionMismatchCounts {
        let playableEvents = plan.noteEvents.filter { (21 ... 108).contains($0.midiNote) }
        let expectedSteps = Set(playableEvents.map {
            StepProjectionIdentity(
                tick: $0.performedOnTick,
                midiNote: $0.midiNote,
                staff: $0.staff,
                voice: $0.voice
            )
        })
        let projectedSteps = Set(steps.flatMap { step in
            step.notes.map {
                StepProjectionIdentity(
                    tick: step.tick,
                    midiNote: $0.midiNote,
                    staff: $0.staff,
                    voice: $0.voice
                )
            }
        })
        let expectedHighlightIDs = playableEvents.map { $0.id.description }
        let projectedHighlightIDs = highlightGuides.flatMap(\.triggeredNotes).map(\.occurrenceID)
        let expectedNotationIDs = Set(plan.noteEvents.map(\.id))
        let projectedNotationIDs = Set(
            notationProjection.performedOccurrences.flatMap(\.performanceEventIDs)
        )

        return ProjectionMismatchCounts(
            steps: expectedSteps.symmetricDifference(projectedSteps).count,
            highlights: cardinalityMismatchCount(
                expected: expectedHighlightIDs,
                projected: projectedHighlightIDs
            ),
            notation: expectedNotationIDs.symmetricDifference(projectedNotationIDs).count
        )
    }

    private static func cardinalityMismatchCount<Value: Hashable>(
        expected: [Value],
        projected: [Value]
    ) -> Int {
        let expectedCounts = Dictionary(expected.map { ($0, 1) }, uniquingKeysWith: +)
        let projectedCounts = Dictionary(projected.map { ($0, 1) }, uniquingKeysWith: +)
        return Set(expectedCounts.keys).union(projectedCounts.keys).reduce(into: 0) { count, key in
            count += abs(expectedCounts[key, default: 0] - projectedCounts[key, default: 0])
        }
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
