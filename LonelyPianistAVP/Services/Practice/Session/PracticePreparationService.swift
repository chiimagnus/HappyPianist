import Foundation

protocol PracticePreparationServiceProtocol {
    func prepare(from scoreURL: URL, file: ImportedMusicXMLFile) throws -> PreparedPractice
}

struct PracticePreparationService: PracticePreparationServiceProtocol {
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

    func prepare(from scoreURL: URL, file: ImportedMusicXMLFile) throws -> PreparedPractice {
        let score = try parser.parse(fileURL: scoreURL)
        let shouldExpandStructure = MusicXMLRealisticPlaybackDefaults.shouldExpandStructure
        let primaryPartIDForExpansion = score.preferredPrimaryPartID()
        let effectiveScore = shouldExpandStructure
            ? structureExpander.expandStructureIfPossible(score: score, primaryPartID: primaryPartIDForExpansion)
            : score
        let primaryPartID = effectiveScore.preferredPrimaryPartID(preferredPartID: primaryPartIDForExpansion)
        let practiceScore = effectiveScore.filtering(toPartID: primaryPartID)

        let expressivityOptions = MusicXMLRealisticPlaybackDefaults.expressivityOptions
        let buildResult = stepBuilder.buildSteps(from: practiceScore, expressivity: expressivityOptions)
        let wordsSemantics = expressivityOptions.wordsSemanticsEnabled
            ? MusicXMLWordsSemanticsInterpreter().interpret(
                wordsEvents: practiceScore.wordsEvents,
                tempoEvents: practiceScore.tempoEvents
            )
            : nil
        let tempoMap = MusicXMLTempoMap(
            tempoEvents: practiceScore.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
            tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
            partID: primaryPartID
        )
        let pedalTimeline = MusicXMLPedalTimeline(events: practiceScore
            .pedalEvents + (wordsSemantics?.derivedPedalEvents ?? []))
        let fermataTimeline = expressivityOptions.fermataEnabled
            ? MusicXMLFermataTimeline(fermataEvents: practiceScore.fermataEvents, notes: practiceScore.notes)
            : nil
        let attributeTimeline = MusicXMLAttributeTimeline(
            timeSignatureEvents: practiceScore.timeSignatureEvents,
            keySignatureEvents: practiceScore.keySignatureEvents,
            clefEvents: practiceScore.clefEvents
        )
        let slurTimeline = MusicXMLSlurTimeline(events: practiceScore.slurEvents)
        let shouldUsePerformanceTiming = MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled
        let noteSpans = MusicXMLNoteSpanBuilder().buildSpans(
            from: practiceScore.notes,
            performanceTimingEnabled: shouldUsePerformanceTiming,
            expressivity: expressivityOptions,
            fermataTimeline: fermataTimeline
        )
        let highlightGuides = PianoHighlightGuideBuilderService().buildGuides(
            input: PianoHighlightGuideBuildInput(
                score: practiceScore,
                steps: buildResult.steps,
                noteSpans: noteSpans,
                expressivity: expressivityOptions
            )
        )

        return PreparedPractice(
            steps: buildResult.steps,
            file: file,
            tempoMap: tempoMap,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            attributeTimeline: attributeTimeline,
            slurTimeline: slurTimeline,
            noteSpans: noteSpans,
            highlightGuides: highlightGuides,
            measureSpans: practiceScore.measures,
            unsupportedNoteCount: buildResult.unsupportedNoteCount
        )
    }
}
