import CryptoKit
import Foundation

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
        let scoreBytes = try Data(contentsOf: scoreURL)
        let revision = SHA256.hash(data: scoreBytes).map { String(format: "%02x", $0) }.joined()

        try Task.checkCancellation()
        let rawScore = try parser.parse(fileURL: scoreURL)
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
}
