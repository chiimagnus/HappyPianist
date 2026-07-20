import Foundation

struct GrandStaffNotationLayoutService {
    private struct ChordKey: Hashable {
        let performedSourceID: String
    }

    private struct ChordCandidate {
        let id: String
        let tick: Int
        let xPosition: Double
        let items: [GrandStaffNotationItem]
        let noteValue: GrandStaffNoteValue
    }

    private struct NotationFacts {
        struct BeamMembership: Equatable {
            let id: String
            let level: Int
            let value: MusicXMLBeamValue
        }

        let chordID: String
        let stem: MusicXMLStem
        let beams: [BeamMembership]
        let meter: MusicXMLMeter?
    }

    private struct RestBreak {
        let tick: Int
        let staffNumber: Int
        let voice: Int
    }

    private struct AccidentalMeasureKey: Hashable {
        let partID: String
        let sourceMeasureIndex: Int
        let occurrenceIndex: Int
        let staffNumber: Int
    }

    private struct AccidentalPitchKey: Hashable {
        let step: String
        let octave: Int
    }

    private enum SpannerKind: String, Hashable {
        case tie
        case slur
        case tuplet
    }

    private struct SpannerKey: Hashable {
        let kind: SpannerKind
        let partID: String
        let voice: Int
        let numberToken: String
        let pitchStep: String?
        let pitchOctave: Int?
        let pitchAlter: Double?
    }

    private struct SpannerEndpoint {
        let id: String
        let sourceOrdinal: Int
        let occurrenceID: String
        let tick: Int
        let staffNumber: Int
        let key: SpannerKey
        let numberToken: String?
        let placementToken: String?
        let bracketToken: String?
        let tupletDisplayNumber: Int?
        let typeToken: String?
    }

    private struct SpannerSegment {
        let kind: SpannerKind
        let start: SpannerEndpoint?
        let end: SpannerEndpoint?
    }

    private struct ClippedSpannerSegment {
        let segment: SpannerSegment
        let startXPosition: Double
        let endXPosition: Double
        let continuesFromPrevious: Bool
        let continuesToNext: Bool
    }

    private let visibleOverscan: Double = 0.18
    private let chordLayoutService: GrandStaffChordLayoutService
    private let horizontalSpacingService: GrandStaffHorizontalSpacingService

    init(
        chordLayoutService: GrandStaffChordLayoutService = GrandStaffChordLayoutService(),
        horizontalSpacingService: GrandStaffHorizontalSpacingService = GrandStaffHorizontalSpacingService()
    ) {
        self.chordLayoutService = chordLayoutService
        self.horizontalSpacingService = horizontalSpacingService
    }

    func makeLayout(
        projection: ScoreNotationProjection,
        overlay: ScoreNotationProjection.Overlay = .empty,
        measureSpans: [MusicXMLMeasureSpan] = [],
        context: GrandStaffNotationContext? = nil,
        viewportWidthStaffSpaces: Double = 36,
        scrollTick: Double? = nil
    ) -> GrandStaffNotationLayout {
        let sourceNotesByID = Dictionary(uniqueKeysWithValues: projection.sourceNotes.map { ($0.id, $0) })
        let occurrences = projection.performedOccurrences.compactMap { occurrence -> LayoutOccurrence? in
            guard let source = sourceNotesByID[occurrence.sourceNoteID] else { return nil }
            return LayoutOccurrence(
                performedID: occurrence.id,
                occurrenceID: occurrence.id.description,
                source: source,
                staffNumber: resolvedStaffNumber(source.staff),
                voice: source.voice,
                hand: occurrence.handAssignment.hand,
                tick: occurrence.writtenOnTick,
                isHighlighted: occurrence.performanceEventIDs.contains { overlay.activeEventIDs.contains($0) }
            )
        }
        let unresolvedNotes = occurrences.compactMap { occurrence -> LayoutNote? in
            let source = occurrence.source
            guard source.isRest == false,
                  source.isPrintObjectVisible,
                  let writtenPitch = source.writtenPitch
            else {
                return nil
            }
            let writtenDurationTicks = max(1, source.writtenDurationTicks)
            return LayoutNote(
                performedID: occurrence.performedID,
                occurrenceID: occurrence.occurrenceID,
                staffNumber: occurrence.staffNumber,
                voice: occurrence.voice,
                hand: occurrence.hand,
                tick: occurrence.tick,
                isHighlighted: occurrence.isHighlighted,
                fingerings: source.fingerings,
                chordID: MusicXMLPerformedNoteID(
                    sourceID: source.chordID,
                    occurrenceIndex: occurrence.performedID.occurrenceIndex
                ).description,
                stem: source.stem,
                beams: source.beams.map {
                    NotationFacts.BeamMembership(
                        id: "\($0.groupID.description)@\(occurrence.performedID.occurrenceIndex)",
                        level: max(1, Int($0.numberToken ?? "1") ?? 1),
                        value: $0.value
                    )
                },
                meter: source.meter,
                noteValue: isSupportedNotehead(source.noteheadToken)
                    ? GrandStaffNoteValue(sourceTypeToken: source.writtenRhythm?.typeToken)
                    : .unsupported(sourceTypeToken: source.noteheadToken),
                durationTicks: writtenDurationTicks,
                writtenPitch: writtenPitch,
                clef: source.clef,
                keySignatureFifths: source.keySignature?.fifths ?? 0,
                displayedAccidental: nil,
                isGrace: source.isGrace,
                articulations: source.articulations,
                arpeggiate: source.arpeggiate,
                dotCount: source.writtenRhythm?.dotCount ?? 0
            )
        }
        let layoutNotes = resolvingDisplayedAccidentals(unresolvedNotes)

        return makeLayout(
            notes: layoutNotes,
            occurrences: occurrences,
            sourceMarks: projection.marks,
            sourceAttributeChanges: projection.attributeChanges,
            activeTickRange: overlay.activeTickRange,
            measureSpans: measureSpans,
            context: context,
            viewportWidthStaffSpaces: viewportWidthStaffSpaces,
            scrollTick: scrollTick
        )
    }

    private struct LayoutOccurrence {
        let performedID: MusicXMLPerformedNoteID
        let occurrenceID: String
        let source: ScoreNotationProjection.SourceNote
        let staffNumber: Int
        let voice: Int
        let hand: ScoreHand
        let tick: Int
        let isHighlighted: Bool
    }

    private struct LayoutNote {
        let performedID: MusicXMLPerformedNoteID
        let occurrenceID: String
        let staffNumber: Int
        let voice: Int
        let hand: ScoreHand
        let tick: Int
        let isHighlighted: Bool
        let fingerings: [MusicXMLFingering]
        let chordID: String
        let stem: MusicXMLStem
        let beams: [NotationFacts.BeamMembership]
        let meter: MusicXMLMeter?
        let noteValue: GrandStaffNoteValue
        let durationTicks: Int
        let writtenPitch: MusicXMLWrittenPitch
        let clef: ScoreNotationProjection.ClefFact?
        let keySignatureFifths: Int
        var displayedAccidental: GrandStaffAccidental?
        let isGrace: Bool
        let articulations: Set<MusicXMLArticulation>
        let arpeggiate: MusicXMLArpeggiate?
        let dotCount: Int
    }

    private func makeLayout(
        notes: [LayoutNote],
        occurrences: [LayoutOccurrence],
        sourceMarks: [ScoreNotationProjection.Mark],
        sourceAttributeChanges: [ScoreNotationProjection.AttributeChange],
        activeTickRange: Range<Int>?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        viewportWidthStaffSpaces: Double,
        scrollTick: Double?
    ) -> GrandStaffNotationLayout {
        let currentTick = scrollTick ?? Double(
            occurrences.first?.tick ?? sourceMarks.first?.tick ?? sourceAttributeChanges.first?.tick ?? 0
        )
        let notationFactsByOccurrenceID = Dictionary(uniqueKeysWithValues: notes.map { note in
            (
                note.occurrenceID,
                NotationFacts(
                    chordID: note.chordID,
                    stem: note.stem,
                    beams: note.beams,
                    meter: note.meter
                )
            )
        })
        let rawItems = notes.map { note in
            GrandStaffNotationItem(
                occurrenceID: note.occurrenceID,
                staffNumber: note.staffNumber,
                voice: note.voice,
                hand: note.hand,
                tick: note.tick,
                xPosition: 0,
                staffStep: staffStep(
                    for: note.writtenPitch,
                    staffNumber: note.staffNumber,
                    clef: note.clef
                ),
                displayedAccidental: note.displayedAccidental,
                isHighlighted: note.isHighlighted,
                fingerings: note.fingerings,
                noteValue: note.noteValue,
                chordID: nil,
                noteheadXOffset: 0,
                accidentalXOffsetStaffSpaces: nil,
                dotXOffsetStaffSpaces: nil,
                dotStaffStep: nil,
                beamID: nil,
                durationTicks: note.durationTicks,
                isGrace: note.isGrace,
                articulations: note.articulations,
                arpeggiate: note.arpeggiate,
                dotCount: note.dotCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
            if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
            if lhs.staffStep != rhs.staffStep { return lhs.staffStep < rhs.staffStep }
            return lhs.occurrenceID < rhs.occurrenceID
        }

        let restBreaks = occurrences.compactMap { occurrence -> RestBreak? in
            guard occurrence.source.isRest else { return nil }
            return RestBreak(
                tick: occurrence.tick,
                staffNumber: occurrence.staffNumber,
                voice: occurrence.voice
            )
        }
        let chordBuild = buildChordsAndBeams(
            items: rawItems,
            notationFactsByOccurrenceID: notationFactsByOccurrenceID,
            measureSpans: measureSpans,
            restBreaks: restBreaks
        )
        let rests = occurrences.compactMap { occurrence -> GrandStaffNotationRest? in
            let source = occurrence.source
            guard source.isRest, source.isPrintObjectVisible
            else { return nil }
            return GrandStaffNotationRest(
                id: occurrence.occurrenceID,
                staffNumber: occurrence.staffNumber,
                voice: occurrence.voice,
                tick: occurrence.tick,
                xPosition: 0,
                noteValue: source.isMeasureRest
                    ? .whole
                    : GrandStaffNoteValue(sourceTypeToken: source.writtenRhythm?.typeToken),
                dotCount: source.isMeasureRest ? 0 : source.writtenRhythm?.dotCount ?? 0,
                isMeasureRest: source.isMeasureRest,
                isHighlighted: occurrence.isHighlighted
            )
        }
        let rawMarks = notationMarks(sourceMarks: sourceMarks, items: chordBuild.items)
        let structuralMarkTicks = Set(rawMarks.compactMap { mark in
            isBarlineMark(mark.kind) ? mark.tick : nil
        })
        let barlineTicks = makeBarlineTicks(measureSpans: measureSpans).union(structuralMarkTicks)
        let attributeTicks = Set(sourceAttributeChanges.map(\.tick))
        let spacing = horizontalSpacingService.makeLayout(
            rhythmicColumns: rhythmicColumns(
                items: chordBuild.items,
                rests: rests,
                ledgerLines: chordBuild.ledgerLines,
                marks: rawMarks
            ),
            barlineTicks: barlineTicks,
            attributeTicks: attributeTicks,
            barlineExtentsByTick: Dictionary(uniqueKeysWithValues: structuralMarkTicks.map { ($0, 0.8) }),
            attributeRightExtentsByTick: attributeRightExtentsByTick(sourceAttributeChanges)
        )
        let safeViewportWidth = max(1, viewportWidthStaffSpaces)
        let scrollPosition = spacing.position(at: currentTick)
        func normalized(_ position: Double) -> Double {
            0.5 + (position - scrollPosition) / safeViewportWidth
        }
        func normalizedTick(_ tick: Int) -> Double {
            normalized(spacing.rhythmicPositionsByTick[tick] ?? spacing.position(at: Double(tick)))
        }

        let positionedItems = chordBuild.items.map { item in
            copy(item: item, xPosition: normalizedTick(item.tick))
        }.filter {
            (activeTickRange?.contains($0.tick) ?? true) &&
                $0.xPosition >= -visibleOverscan && $0.xPosition <= 1 + visibleOverscan
        }
        let visibleItemIDs = Set(positionedItems.map(\.id))
        let visibleChordIDs = Set(positionedItems.compactMap(\.chordID))
        let positionedChords = chordBuild.chords.compactMap { chord -> GrandStaffNotationChord? in
            guard visibleChordIDs.contains(chord.id) else { return nil }
            return GrandStaffNotationChord(
                id: chord.id,
                tick: chord.tick,
                xPosition: normalizedTick(chord.tick),
                itemIDs: chord.itemIDs.filter { visibleItemIDs.contains($0) },
                stem: chord.stem,
                noteValue: chord.noteValue
            )
        }
        let positionedRests = rests.map { rest in
            let position: Double
            if rest.isMeasureRest,
               let measure = measureSpans.first(where: {
                   $0.startTick <= rest.tick && rest.tick < $0.endTick
               })
            {
                let startPosition = spacing.barlinePositionsByTick[measure.startTick]
                    ?? spacing.rhythmicPositionsByTick[measure.startTick]
                    ?? spacing.position(at: Double(measure.startTick))
                let endPosition = spacing.barlinePositionsByTick[measure.endTick]
                    ?? spacing.position(at: Double(measure.endTick))
                position = normalized((startPosition + endPosition) / 2)
            } else {
                position = normalizedTick(rest.tick)
            }
            return GrandStaffNotationRest(
                id: rest.id,
                staffNumber: rest.staffNumber,
                voice: rest.voice,
                tick: rest.tick,
                xPosition: position,
                noteValue: rest.noteValue,
                dotCount: rest.dotCount,
                isMeasureRest: rest.isMeasureRest,
                isHighlighted: rest.isHighlighted
            )
        }.filter {
            (activeTickRange?.contains($0.tick) ?? true) &&
                $0.xPosition >= -visibleOverscan && $0.xPosition <= 1 + visibleOverscan
        }
        let positionedLedgerLines = chordBuild.ledgerLines.map { ledgerLine in
            GrandStaffNotationLedgerLine(
                id: ledgerLine.id,
                tick: ledgerLine.tick,
                xPosition: normalizedTick(ledgerLine.tick),
                staffNumber: ledgerLine.staffNumber,
                staffStep: ledgerLine.staffStep,
                minXOffsetStaffSpaces: ledgerLine.minXOffsetStaffSpaces,
                maxXOffsetStaffSpaces: ledgerLine.maxXOffsetStaffSpaces
            )
        }.filter { $0.xPosition >= -visibleOverscan && $0.xPosition <= 1 + visibleOverscan }
        let positionedBarlines = barlineTicks.sorted().compactMap { tick -> GrandStaffNotationBarline? in
            guard let position = spacing.barlinePositionsByTick[tick] else { return nil }
            let xPosition = normalized(position)
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return GrandStaffNotationBarline(id: "barline-\(tick)", tick: tick, xPosition: xPosition)
        }
        let positionedMarks = rawMarks.compactMap { mark -> GrandStaffNotationMark? in
            let position = isBarlineMark(mark.kind)
                ? spacing.barlinePositionsByTick[mark.tick]
                : spacing.rhythmicPositionsByTick[mark.tick] ?? spacing.position(at: Double(mark.tick))
            guard let position else { return nil }
            let positioned = copy(mark: mark, xPosition: normalized(position))
            guard positioned.xPosition >= -visibleOverscan,
                  positioned.xPosition <= 1 + visibleOverscan,
                  activeTickRange?.contains(positioned.tick) ?? true
            else { return nil }
            return positioned
        }
        let positionedAttributeChanges = sourceAttributeChanges.compactMap { change -> GrandStaffNotationAttributeChange? in
            guard let position = spacing.attributePositionsByTick[change.tick] else { return nil }
            let xPosition = normalized(position)
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return GrandStaffNotationAttributeChange(
                id: change.id,
                tick: change.tick,
                xPosition: xPosition,
                staffNumber: change.staff,
                clefSignToken: change.clef?.signToken,
                clefLine: change.clef?.line,
                keySignatureFifths: change.keySignatureFifths,
                previousKeySignatureFifths: change.previousKeySignatureFifths,
                timeSignatureText: change.meterText
            )
        }
        let spanners = clippedSpannerSegments(
            occurrences: occurrences,
            activeTickRange: activeTickRange,
            spacing: spacing,
            scrollPosition: scrollPosition,
            viewportWidthStaffSpaces: safeViewportWidth
        )

        return GrandStaffNotationLayout(
            items: positionedItems,
            chords: positionedChords,
            rests: positionedRests,
            ties: spanners.compactMap(makeTie),
            slurs: spanners.compactMap(makeSlur),
            tuplets: makeTuplets(spanners),
            barlines: positionedBarlines,
            beams: clippedBeams(chordBuild.beams, visibleChordIDs: visibleChordIDs),
            ledgerLines: positionedLedgerLines,
            marks: positionedMarks,
            attributeChanges: positionedAttributeChanges,
            context: context
        )
    }

    private func clippedSpannerSegments(
        occurrences: [LayoutOccurrence],
        activeTickRange: Range<Int>?,
        spacing: GrandStaffHorizontalSpacingService.Layout,
        scrollPosition: Double,
        viewportWidthStaffSpaces: Double
    ) -> [ClippedSpannerSegment] {
        let viewportLower = scrollPosition + (-visibleOverscan - 0.5) * viewportWidthStaffSpaces
        let viewportUpper = scrollPosition + (1 + visibleOverscan - 0.5) * viewportWidthStaffSpaces
        let lowerPosition = max(
            viewportLower,
            activeTickRange.map { spacing.position(at: Double($0.lowerBound)) } ?? viewportLower
        )
        let upperPosition = min(
            viewportUpper,
            activeTickRange.map { spacing.position(at: Double($0.upperBound)) } ?? viewportUpper
        )
        guard lowerPosition < upperPosition else { return [] }

        return pairedSpannerSegments(occurrences: occurrences).compactMap { segment in
            let startTick = segment.start?.tick
            let endTick = segment.end?.tick
            if let activeTickRange {
                guard (startTick ?? Int.min) < activeTickRange.upperBound,
                      (endTick ?? Int.max) >= activeTickRange.lowerBound
                else { return nil }
            }
            let startPosition = segment.start.map { spacing.position(at: Double($0.tick)) }
            let endPosition = segment.end.map { spacing.position(at: Double($0.tick)) }
            guard (startPosition ?? -.infinity) < upperPosition,
                  (endPosition ?? .infinity) >= lowerPosition
            else {
                return nil
            }
            let continuesFromPrevious = startPosition == nil || startPosition! < viewportLower ||
                activeTickRange.map { (startTick ?? Int.min) < $0.lowerBound } == true
            let continuesToNext = endPosition == nil || endPosition! >= viewportUpper ||
                activeTickRange.map { (endTick ?? Int.max) >= $0.upperBound } == true
            let clippedStart = max(startPosition ?? lowerPosition, lowerPosition)
            let clippedEnd = min(endPosition ?? upperPosition, upperPosition)
            guard clippedStart <= clippedEnd else { return nil }
            return ClippedSpannerSegment(
                segment: segment,
                startXPosition: 0.5 + (clippedStart - scrollPosition) / viewportWidthStaffSpaces,
                endXPosition: 0.5 + (clippedEnd - scrollPosition) / viewportWidthStaffSpaces,
                continuesFromPrevious: continuesFromPrevious,
                continuesToNext: continuesToNext
            )
        }
    }

    private func pairedSpannerSegments(occurrences: [LayoutOccurrence]) -> [SpannerSegment] {
        let endpoints = occurrences.flatMap(spannerEndpoints).sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.occurrenceID != rhs.occurrenceID { return lhs.occurrenceID < rhs.occurrenceID }
            if lhs.sourceOrdinal != rhs.sourceOrdinal { return lhs.sourceOrdinal < rhs.sourceOrdinal }
            return lhs.id < rhs.id
        }
        var activeByKey: [SpannerKey: [SpannerEndpoint]] = [:]
        var segments: [SpannerSegment] = []

        for endpoint in endpoints {
            switch endpoint.typeToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "start":
                activeByKey[endpoint.key, default: []].append(endpoint)
            case "stop":
                let start = activeByKey[endpoint.key]?.popLast()
                if activeByKey[endpoint.key]?.isEmpty == true {
                    activeByKey.removeValue(forKey: endpoint.key)
                }
                segments.append(SpannerSegment(kind: endpoint.key.kind, start: start, end: endpoint))
            case "continue":
                continue
            default:
                continue
            }
        }
        for endpoints in activeByKey.values {
            segments.append(contentsOf: endpoints.map {
                SpannerSegment(kind: $0.key.kind, start: $0, end: nil)
            })
        }
        return segments.sorted { lhs, rhs in
            let lhsTick = lhs.start?.tick ?? lhs.end?.tick ?? Int.min
            let rhsTick = rhs.start?.tick ?? rhs.end?.tick ?? Int.min
            if lhsTick != rhsTick { return lhsTick < rhsTick }
            return spannerID(lhs) < spannerID(rhs)
        }
    }

    private func spannerEndpoints(for occurrence: LayoutOccurrence) -> [SpannerEndpoint] {
        let source = occurrence.source
        let tieEndpoints = source.ties.enumerated().compactMap { ordinal, tie -> SpannerEndpoint? in
            guard tie.sourceElement == .notation else { return nil }
            return spannerEndpoint(
                kind: .tie,
                sourceID: tie.sourceID,
                fallbackOrdinal: ordinal,
                typeToken: tie.typeToken,
                numberToken: tie.numberToken,
                placementToken: tie.placementToken,
                bracketToken: nil,
                tupletDisplayNumber: nil,
                occurrence: occurrence,
                writtenPitch: source.writtenPitch
            )
        }
        let slurEndpoints = source.slurs.enumerated().map { ordinal, slur in
            spannerEndpoint(
                kind: .slur,
                sourceID: slur.sourceID,
                fallbackOrdinal: ordinal,
                typeToken: slur.typeToken,
                numberToken: slur.numberToken,
                placementToken: slur.placementToken,
                bracketToken: nil,
                tupletDisplayNumber: nil,
                occurrence: occurrence,
                writtenPitch: nil
            )
        }
        let tupletEndpoints = source.tuplets.enumerated().map { ordinal, tuplet in
            spannerEndpoint(
                kind: .tuplet,
                sourceID: tuplet.sourceID,
                fallbackOrdinal: ordinal,
                typeToken: tuplet.typeToken,
                numberToken: tuplet.numberToken,
                placementToken: tuplet.placementToken,
                bracketToken: tuplet.bracketToken,
                tupletDisplayNumber: source.writtenRhythm?.timeModification?.actualNotes,
                occurrence: occurrence,
                writtenPitch: nil
            )
        }
        return tieEndpoints + slurEndpoints + tupletEndpoints
    }

    private func spannerEndpoint(
        kind: SpannerKind,
        sourceID: MusicXMLPerformanceNotationSourceID?,
        fallbackOrdinal: Int,
        typeToken: String?,
        numberToken: String?,
        placementToken: String?,
        bracketToken: String?,
        tupletDisplayNumber: Int?,
        occurrence: LayoutOccurrence,
        writtenPitch: MusicXMLWrittenPitch?
    ) -> SpannerEndpoint {
        let normalizedNumber = normalizedSpannerNumber(numberToken)
        let localID = sourceID?.description ?? "\(kind.rawValue):\(fallbackOrdinal)"
        return SpannerEndpoint(
            id: "\(occurrence.occurrenceID):\(localID)",
            sourceOrdinal: sourceID?.sourceOrdinal ?? fallbackOrdinal,
            occurrenceID: occurrence.occurrenceID,
            tick: occurrence.tick,
            staffNumber: occurrence.staffNumber,
            key: SpannerKey(
                kind: kind,
                partID: occurrence.performedID.sourceID.partID,
                voice: occurrence.voice,
                numberToken: normalizedNumber,
                pitchStep: writtenPitch?.step,
                pitchOctave: writtenPitch?.octave,
                pitchAlter: writtenPitch?.alter
            ),
            numberToken: numberToken,
            placementToken: placementToken,
            bracketToken: bracketToken,
            tupletDisplayNumber: tupletDisplayNumber,
            typeToken: typeToken
        )
    }

    private func makeTie(_ clipped: ClippedSpannerSegment) -> GrandStaffNotationTie? {
        guard clipped.segment.kind == .tie, let endpoint = clipped.segment.start ?? clipped.segment.end else { return nil }
        return GrandStaffNotationTie(
            id: spannerID(clipped.segment),
            staffNumber: endpoint.staffNumber,
            voice: endpoint.key.voice,
            numberToken: clipped.segment.start?.numberToken ?? clipped.segment.end?.numberToken,
            placementToken: clipped.segment.start?.placementToken ?? clipped.segment.end?.placementToken,
            startOccurrenceID: clipped.continuesFromPrevious ? nil : clipped.segment.start?.occurrenceID,
            endOccurrenceID: clipped.continuesToNext ? nil : clipped.segment.end?.occurrenceID,
            startXPosition: clipped.startXPosition,
            endXPosition: clipped.endXPosition,
            continuesFromPrevious: clipped.continuesFromPrevious,
            continuesToNext: clipped.continuesToNext
        )
    }

    private func makeSlur(_ clipped: ClippedSpannerSegment) -> GrandStaffNotationSlur? {
        guard clipped.segment.kind == .slur, let endpoint = clipped.segment.start ?? clipped.segment.end else { return nil }
        return GrandStaffNotationSlur(
            id: spannerID(clipped.segment),
            staffNumber: endpoint.staffNumber,
            voice: endpoint.key.voice,
            numberToken: clipped.segment.start?.numberToken ?? clipped.segment.end?.numberToken,
            placementToken: clipped.segment.start?.placementToken ?? clipped.segment.end?.placementToken,
            startOccurrenceID: clipped.continuesFromPrevious ? nil : clipped.segment.start?.occurrenceID,
            endOccurrenceID: clipped.continuesToNext ? nil : clipped.segment.end?.occurrenceID,
            startXPosition: clipped.startXPosition,
            endXPosition: clipped.endXPosition,
            continuesFromPrevious: clipped.continuesFromPrevious,
            continuesToNext: clipped.continuesToNext
        )
    }

    private func makeTuplet(_ clipped: ClippedSpannerSegment) -> GrandStaffNotationTuplet? {
        guard clipped.segment.kind == .tuplet, let endpoint = clipped.segment.start ?? clipped.segment.end else { return nil }
        return GrandStaffNotationTuplet(
            id: spannerID(clipped.segment),
            staffNumber: endpoint.staffNumber,
            voice: endpoint.key.voice,
            numberToken: clipped.segment.start?.numberToken ?? clipped.segment.end?.numberToken,
            displayNumber: clipped.segment.start?.tupletDisplayNumber ?? clipped.segment.end?.tupletDisplayNumber,
            bracketToken: clipped.segment.start?.bracketToken ?? clipped.segment.end?.bracketToken,
            placementToken: clipped.segment.start?.placementToken ?? clipped.segment.end?.placementToken,
            startOccurrenceID: clipped.continuesFromPrevious ? nil : clipped.segment.start?.occurrenceID,
            endOccurrenceID: clipped.continuesToNext ? nil : clipped.segment.end?.occurrenceID,
            startXPosition: clipped.startXPosition,
            endXPosition: clipped.endXPosition,
            continuesFromPrevious: clipped.continuesFromPrevious,
            continuesToNext: clipped.continuesToNext,
            nestingLevel: 0
        )
    }

    private func makeTuplets(_ spanners: [ClippedSpannerSegment]) -> [GrandStaffNotationTuplet] {
        let rawTuplets = spanners.compactMap(makeTuplet).sorted {
            if $0.startXPosition != $1.startXPosition { return $0.startXPosition < $1.startXPosition }
            if $0.endXPosition != $1.endXPosition { return $0.endXPosition > $1.endXPosition }
            return $0.id < $1.id
        }
        var result: [GrandStaffNotationTuplet] = []
        for tuplet in rawTuplets {
            let nestingLevel = result.filter {
                $0.staffNumber == tuplet.staffNumber &&
                    $0.voice == tuplet.voice &&
                    $0.startXPosition <= tuplet.startXPosition &&
                    $0.endXPosition >= tuplet.endXPosition
            }.count
            result.append(GrandStaffNotationTuplet(
                id: tuplet.id,
                staffNumber: tuplet.staffNumber,
                voice: tuplet.voice,
                numberToken: tuplet.numberToken,
                displayNumber: tuplet.displayNumber,
                bracketToken: tuplet.bracketToken,
                placementToken: tuplet.placementToken,
                startOccurrenceID: tuplet.startOccurrenceID,
                endOccurrenceID: tuplet.endOccurrenceID,
                startXPosition: tuplet.startXPosition,
                endXPosition: tuplet.endXPosition,
                continuesFromPrevious: tuplet.continuesFromPrevious,
                continuesToNext: tuplet.continuesToNext,
                nestingLevel: nestingLevel
            ))
        }
        return result
    }

    private func spannerID(_ segment: SpannerSegment) -> String {
        "\(segment.kind.rawValue):\(segment.start?.id ?? "boundary"):\(segment.end?.id ?? "boundary")"
    }

    private func normalizedSpannerNumber(_ numberToken: String?) -> String {
        let trimmed = numberToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "1" : trimmed
    }

    func staffStep(
        for writtenPitch: MusicXMLWrittenPitch,
        staffNumber: Int,
        clef: ScoreNotationProjection.ClefFact?
    ) -> Int {
        let fallbackBottomLine = staffNumber >= 2
            ? writtenDiatonicIndex(step: "G", octave: 2)
            : writtenDiatonicIndex(step: "E", octave: 4)
        guard let clef,
              let line = clef.line,
              (1 ... 5).contains(line),
              let referencePitch = clefReferencePitch(signToken: clef.signToken)
        else {
            return writtenDiatonicIndex(step: writtenPitch.step, octave: writtenPitch.octave)
                - fallbackBottomLine
        }
        let bottomLineIndex = writtenDiatonicIndex(
            step: referencePitch.step,
            octave: referencePitch.octave
        ) - (line - 1) * 2
        return writtenDiatonicIndex(step: writtenPitch.step, octave: writtenPitch.octave) - bottomLineIndex
    }

    private func clefReferencePitch(signToken: String?) -> (step: String, octave: Int)? {
        switch signToken?.uppercased() {
        case "G": ("G", 4)
        case "F": ("F", 3)
        case "C": ("C", 4)
        default: nil
        }
    }

    private func resolvingDisplayedAccidentals(_ notes: [LayoutNote]) -> [LayoutNote] {
        var accidentalState: [AccidentalMeasureKey: [AccidentalPitchKey: Double]] = [:]
        return notes.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
            if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
            return lhs.occurrenceID < rhs.occurrenceID
        }.map { note in
            let writtenPitch = note.writtenPitch
            let performedID = note.performedID
            let measureKey = AccidentalMeasureKey(
                partID: performedID.sourceID.partID,
                sourceMeasureIndex: performedID.sourceID.sourceMeasureIndex,
                occurrenceIndex: performedID.occurrenceIndex,
                staffNumber: note.staffNumber
            )
            let pitchKey = AccidentalPitchKey(step: writtenPitch.step, octave: writtenPitch.octave)
            let expectedAlter = accidentalState[measureKey]?[pitchKey]
                ?? keySignatureAlter(step: writtenPitch.step, fifths: note.keySignatureFifths)
            var resolved = note
            if writtenPitch.accidentalToken != nil || writtenPitch.alter != expectedAlter {
                resolved.displayedAccidental = accidental(
                    alter: writtenPitch.alter,
                    sourceToken: writtenPitch.accidentalToken
                )
            }
            accidentalState[measureKey, default: [:]][pitchKey] = writtenPitch.alter
            return resolved
        }
    }

    private func accidental(alter: Double, sourceToken: String?) -> GrandStaffAccidental {
        let normalizedToken = sourceToken?.lowercased()
        let kind: GrandStaffAccidental.Kind = switch normalizedToken {
        case "sharp": .sharp
        case "flat": .flat
        case "natural": .natural
        case "double-sharp", "sharp-sharp": .doubleSharp
        case "flat-flat", "double-flat": .doubleFlat
        case .some: .unsupported
        case nil:
            switch alter {
            case 1: .sharp
            case -1: .flat
            case 0: .natural
            case 2: .doubleSharp
            case -2: .doubleFlat
            default: .unsupported
            }
        }
        return GrandStaffAccidental(kind: kind, sourceToken: sourceToken, alter: alter)
    }

    private func keySignatureAlter(step: String, fifths: Int) -> Double {
        let clamped = max(-7, min(7, fifths))
        let orderedSteps = clamped >= 0
            ? ["F", "C", "G", "D", "A", "E", "B"]
            : ["B", "E", "A", "D", "G", "C", "F"]
        return orderedSteps.prefix(abs(clamped)).contains(step.uppercased()) ? (clamped >= 0 ? 1 : -1) : 0
    }

    private func writtenDiatonicIndex(step: String, octave: Int) -> Int {
        let stepIndex = ["C": 0, "D": 1, "E": 2, "F": 3, "G": 4, "A": 5, "B": 6][step.uppercased()] ?? 0
        return octave * 7 + stepIndex
    }

    private func ledgerStaffSteps(for staffStep: Int) -> [Int] {
        guard staffStep < 0 || staffStep > 8 else { return [] }

        var steps: [Int] = []
        if staffStep < 0 {
            var cursor = staffStep
            while cursor < 0 {
                if cursor % 2 == 0 { steps.append(cursor) }
                cursor += 1
            }
        } else {
            var cursor = staffStep
            while cursor > 8 {
                if cursor % 2 == 0 { steps.append(cursor) }
                cursor -= 1
            }
        }
        return steps
    }

    private func isSupportedNotehead(_ token: String?) -> Bool {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.isEmpty || normalized == "normal"
    }

    private func makeBarlineTicks(measureSpans: [MusicXMLMeasureSpan]) -> Set<Int> {
        guard let headerStartTick = measureSpans.map(\.startTick).min() else { return [] }
        var ticks = Set(measureSpans.flatMap { [$0.startTick, $0.endTick] })
        // ponytail: the fixed clef/key/meter header owns the first measure start; pagination can add system-start rules later.
        ticks.remove(headerStartTick)
        return ticks
    }

    private func notationMarks(
        sourceMarks: [ScoreNotationProjection.Mark],
        items: [GrandStaffNotationItem]
    ) -> [GrandStaffNotationMark] {
        var marks = sourceMarks.compactMap { source -> GrandStaffNotationMark? in
            guard source.kind != .pedalContinue else { return nil }
            let kind: GrandStaffNotationMark.Kind = switch source.kind {
            case .dynamic: .dynamic
            case .tempo: .tempo
            case .text: .text
            case .pedalStart: .pedalStart
            case .pedalStop: .pedalStop
            case .pedalChange: .pedalChange
            case .pedalContinue: .pedalContinue
            case .fermata: .fermata
            case .repeatForward: .repeatForward
            case .repeatBackward: .repeatBackward
            case .endingStart: .endingStart
            case .endingStop: .endingStop
            case .endingDiscontinue: .endingDiscontinue
            }
            let voice = source.voice ?? 1
            let matchingItems = items.filter {
                $0.tick == source.tick &&
                    (source.staff == nil || $0.staffNumber == resolvedStaffNumber(source.staff)) &&
                    (source.voice == nil || $0.voice == source.voice)
            }
            let staffNumber = source.staff.map(resolvedStaffNumber)
                ?? matchingItems.first?.staffNumber
                ?? (kind == .pedalStart || kind == .pedalStop || kind == .pedalChange ? 2 : 1)
            let placement = resolvedMarkPlacement(
                sourceToken: source.placementToken,
                kind: kind,
                voice: voice
            )
            let anchorsToNote = kind == .fermata
            return GrandStaffNotationMark(
                id: source.id,
                tick: source.tick,
                xPosition: 0,
                staffNumber: staffNumber,
                voice: voice,
                kind: kind,
                text: source.text,
                placement: placement,
                collisionLevel: 0,
                minimumStaffStep: anchorsToNote ? matchingItems.map(\.staffStep).min() : nil,
                maximumStaffStep: anchorsToNote ? matchingItems.map(\.staffStep).max() : nil,
                minimumStaffNumber: anchorsToNote ? staffNumber : nil,
                maximumStaffNumber: anchorsToNote ? staffNumber : nil
            )
        }

        for item in items {
            for (index, token) in item.articulationGlyphTokens.enumerated() {
                let placement = resolvedMarkPlacement(sourceToken: nil, kind: .articulation(token), voice: item.voice)
                marks.append(GrandStaffNotationMark(
                    id: "\(item.id):articulation:\(index)",
                    tick: item.tick,
                    xPosition: 0,
                    staffNumber: item.staffNumber,
                    voice: item.voice,
                    kind: .articulation(token),
                    text: nil,
                    placement: placement,
                    collisionLevel: 0,
                    minimumStaffStep: item.staffStep,
                    maximumStaffStep: item.staffStep,
                    minimumStaffNumber: item.staffNumber,
                    maximumStaffNumber: item.staffNumber
                ))
            }
            for (index, fingering) in item.fingerings.enumerated() where fingering.text.isEmpty == false {
                let placement = resolvedMarkPlacement(
                    sourceToken: fingering.placementToken,
                    kind: .fingering,
                    voice: item.voice
                )
                marks.append(GrandStaffNotationMark(
                    id: fingering.sourceID?.description ?? "\(item.id):fingering:\(index)",
                    tick: item.tick,
                    xPosition: 0,
                    staffNumber: item.staffNumber,
                    voice: item.voice,
                    kind: .fingering,
                    text: fingering.text,
                    placement: placement,
                    collisionLevel: 0,
                    minimumStaffStep: item.staffStep,
                    maximumStaffStep: item.staffStep,
                    minimumStaffNumber: item.staffNumber,
                    maximumStaffNumber: item.staffNumber
                ))
            }
        }

        let arpeggioItems = Dictionary(grouping: items.filter { item in
            guard let arpeggiate = item.arpeggiate else { return false }
            return arpeggiate.directionToken == nil || arpeggiate.direction != nil
        }) { item in
            "\(item.chordID ?? item.id):\(item.arpeggiate?.normalizedNumberToken ?? "1")"
        }
        for (id, chordItems) in arpeggioItems {
            guard let first = chordItems.first, let arpeggiate = first.arpeggiate else { continue }
            let lowerStaffNumber = chordItems.map(\.staffNumber).max() ?? first.staffNumber
            let upperStaffNumber = chordItems.map(\.staffNumber).min() ?? first.staffNumber
            let lowerStaffStep = chordItems
                .filter { $0.staffNumber == lowerStaffNumber }
                .map(\.staffStep)
                .min()
            let upperStaffStep = chordItems
                .filter { $0.staffNumber == upperStaffNumber }
                .map(\.staffStep)
                .max()
            let token: GrandStaffGlyphToken = switch arpeggiate.direction {
            case .up: .arpeggiatoUp
            case .down: .arpeggiatoDown
            case nil: .arpeggiato
            }
            marks.append(GrandStaffNotationMark(
                id: "\(id):arpeggio",
                tick: first.tick,
                xPosition: 0,
                staffNumber: first.staffNumber,
                voice: first.voice,
                kind: .arpeggio(token),
                text: nil,
                placement: .left,
                collisionLevel: 0,
                minimumStaffStep: lowerStaffStep,
                maximumStaffStep: upperStaffStep,
                minimumStaffNumber: lowerStaffNumber,
                maximumStaffNumber: upperStaffNumber
            ))
        }

        var nextLevelByCollisionKey: [String: Int] = [:]
        return marks.sorted {
            if $0.tick != $1.tick { return $0.tick < $1.tick }
            if $0.staffNumber != $1.staffNumber { return $0.staffNumber < $1.staffNumber }
            return $0.id < $1.id
        }.map { mark in
            let key = "\(mark.tick):\(mark.staffNumber):\(mark.placement)"
            let level = nextLevelByCollisionKey[key, default: 0]
            nextLevelByCollisionKey[key] = level + 1
            return GrandStaffNotationMark(
                id: mark.id,
                tick: mark.tick,
                xPosition: mark.xPosition,
                staffNumber: mark.staffNumber,
                voice: mark.voice,
                kind: mark.kind,
                text: mark.text,
                placement: mark.placement,
                collisionLevel: level,
                minimumStaffStep: mark.minimumStaffStep,
                maximumStaffStep: mark.maximumStaffStep,
                minimumStaffNumber: mark.minimumStaffNumber,
                maximumStaffNumber: mark.maximumStaffNumber
            )
        }
    }

    private func resolvedMarkPlacement(
        sourceToken: String?,
        kind: GrandStaffNotationMark.Kind,
        voice: Int
    ) -> GrandStaffNotationPlacement {
        switch sourceToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "above": return .above
        case "below": return .below
        default: break
        }
        return switch kind {
        case .tempo, .text, .endingStart, .endingStop, .endingDiscontinue: .above
        case .dynamic, .pedalStart, .pedalStop, .pedalChange, .pedalContinue: .below
        case .repeatForward, .repeatBackward, .arpeggio: .left
        case .fermata, .articulation, .fingering: voice.isMultiple(of: 2) ? .below : .above
        }
    }

    private func isBarlineMark(_ kind: GrandStaffNotationMark.Kind) -> Bool {
        switch kind {
        case .repeatForward, .repeatBackward, .endingStart, .endingStop, .endingDiscontinue: true
        default: false
        }
    }

    private func attributeRightExtentsByTick(
        _ changes: [ScoreNotationProjection.AttributeChange]
    ) -> [Int: Double] {
        Dictionary(grouping: changes, by: \.tick).mapValues { changesAtTick in
            changesAtTick.map { change in
                let clefWidth = change.clef == nil ? 0 : 1.7
                let cancellationWidth = Double(abs(change.previousKeySignatureFifths ?? 0)) * 0.78
                let keyWidth = Double(abs(change.keySignatureFifths ?? 0)) * 0.78
                let meterWidth = change.meterText == nil ? 0 : 1.8
                return max(1.1, clefWidth + cancellationWidth + keyWidth + meterWidth + 0.8)
            }.max() ?? 1.1
        }
    }

    private func rhythmicColumns(
        items: [GrandStaffNotationItem],
        rests: [GrandStaffNotationRest],
        ledgerLines: [GrandStaffNotationLedgerLine],
        marks: [GrandStaffNotationMark]
    ) -> [GrandStaffHorizontalSpacingService.RhythmicColumn] {
        let metrics = GrandStaffEngravingMetrics()
        var columns: [GrandStaffHorizontalSpacingService.RhythmicColumn] = []
        for item in items {
            let scale = metrics.glyphScale(isGrace: item.isGrace)
            let noteheadBounds = item.noteheadGlyphToken.flatMap(metrics.bounds) ?? metrics.noteheadViewportBounds
            let noteheadCenter = item.noteheadXOffset * metrics.noteheadColumnWidth * scale
            var minX = noteheadCenter + noteheadBounds.minX * scale
            var maxX = noteheadCenter + noteheadBounds.maxX * scale
            if let token = item.displayedAccidental?.glyphToken,
               let center = item.accidentalXOffsetStaffSpaces,
               let bounds = metrics.bounds(for: token) {
                minX = min(minX, center + bounds.minX * scale)
                maxX = max(maxX, center + bounds.maxX * scale)
            }
            if item.dotCount > 0,
               let center = item.dotXOffsetStaffSpaces,
               let bounds = metrics.bounds(for: .augmentationDot) {
                maxX = max(
                    maxX,
                    center + bounds.maxX * scale + Double(item.dotCount - 1) * metrics.dotSpacing
                )
            }
            columns.append(.init(
                tick: item.tick,
                durationTicks: item.durationTicks,
                leftExtent: max(0, -minX),
                rightExtent: max(0, maxX)
            ))
        }
        for rest in rests {
            let bounds = rest.glyphToken.flatMap(metrics.bounds) ?? metrics.noteheadViewportBounds
            let dottedRight = bounds.maxX + metrics.dotNoteheadGap
                + Double(rest.dotCount) * metrics.dotSpacing
            columns.append(.init(
                tick: rest.tick,
                durationTicks: durationTicks(for: rest.noteValue),
                leftExtent: max(0, -bounds.minX),
                rightExtent: max(bounds.maxX, dottedRight)
            ))
        }
        for ledgerLine in ledgerLines {
            columns.append(.init(
                tick: ledgerLine.tick,
                durationTicks: items.first { $0.tick == ledgerLine.tick }?.durationTicks ?? MusicXMLTempoMap.ticksPerQuarter,
                leftExtent: max(0, -ledgerLine.minXOffsetStaffSpaces),
                rightExtent: max(0, ledgerLine.maxXOffsetStaffSpaces)
            ))
        }
        for mark in marks where isBarlineMark(mark.kind) == false {
            let duration = items.first { $0.tick == mark.tick }?.durationTicks ?? MusicXMLTempoMap.ticksPerQuarter
            let extents = markHorizontalExtents(mark, metrics: metrics)
            columns.append(.init(
                tick: mark.tick,
                durationTicks: duration,
                leftExtent: extents.left,
                rightExtent: extents.right
            ))
        }
        return columns
    }

    private func markHorizontalExtents(
        _ mark: GrandStaffNotationMark,
        metrics: GrandStaffEngravingMetrics
    ) -> (left: Double, right: Double) {
        if case let .arpeggio(token) = mark.kind {
            return (left: (metrics.bounds(for: token)?.width ?? 0.9) + 0.45, right: 0)
        }
        if let token = mark.glyphToken, let bounds = metrics.bounds(for: token) {
            return switch mark.kind {
            case .pedalChange:
                (0.15, bounds.width * 0.75 + (metrics.bounds(for: .keyboardPedalPed)?.width ?? 4.1) * 0.75 + 1.75)
            case .pedalStart, .pedalStop: (0.15, bounds.width + 0.15)
            default: (bounds.width / 2 + 0.15, bounds.width / 2 + 0.15)
            }
        }
        let textWidth = max(0.8, Double(mark.text?.count ?? 0) * 0.55)
        return switch mark.kind {
        case .tempo, .text: (0.15, textWidth + 0.15)
        default: (textWidth / 2 + 0.15, textWidth / 2 + 0.15)
        }
    }

    private func durationTicks(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
        case .whole: MusicXMLTempoMap.ticksPerQuarter * 4
        case .half: MusicXMLTempoMap.ticksPerQuarter * 2
        case .quarter, .unsupported: MusicXMLTempoMap.ticksPerQuarter
        case .eighth: MusicXMLTempoMap.ticksPerQuarter / 2
        case .sixteenth: MusicXMLTempoMap.ticksPerQuarter / 4
        case .thirtySecond: MusicXMLTempoMap.ticksPerQuarter / 8
        case .sixtyFourth: MusicXMLTempoMap.ticksPerQuarter / 16
        case .oneHundredTwentyEighth: MusicXMLTempoMap.ticksPerQuarter / 32
        }
    }

    private func copy(item: GrandStaffNotationItem, xPosition: Double) -> GrandStaffNotationItem {
        GrandStaffNotationItem(
            occurrenceID: item.occurrenceID,
            staffNumber: item.staffNumber,
            voice: item.voice,
            hand: item.hand,
            tick: item.tick,
            xPosition: xPosition,
            staffStep: item.staffStep,
            displayedAccidental: item.displayedAccidental,
            isHighlighted: item.isHighlighted,
            fingerings: item.fingerings,
            noteValue: item.noteValue,
            chordID: item.chordID,
            noteheadXOffset: item.noteheadXOffset,
            accidentalXOffsetStaffSpaces: item.accidentalXOffsetStaffSpaces,
            dotXOffsetStaffSpaces: item.dotXOffsetStaffSpaces,
            dotStaffStep: item.dotStaffStep,
            beamID: item.beamID,
            durationTicks: item.durationTicks,
            isGrace: item.isGrace,
            articulations: item.articulations,
            arpeggiate: item.arpeggiate,
            dotCount: item.dotCount
        )
    }

    private func copy(mark: GrandStaffNotationMark, xPosition: Double) -> GrandStaffNotationMark {
        GrandStaffNotationMark(
            id: mark.id,
            tick: mark.tick,
            xPosition: xPosition,
            staffNumber: mark.staffNumber,
            voice: mark.voice,
            kind: mark.kind,
            text: mark.text,
            placement: mark.placement,
            collisionLevel: mark.collisionLevel,
            minimumStaffStep: mark.minimumStaffStep,
            maximumStaffStep: mark.maximumStaffStep,
            minimumStaffNumber: mark.minimumStaffNumber,
            maximumStaffNumber: mark.maximumStaffNumber
        )
    }

    private func clippedBeams(
        _ beams: [GrandStaffNotationBeam],
        visibleChordIDs: Set<String>
    ) -> [GrandStaffNotationBeam] {
        beams.compactMap { beam in
            let indexByChordID = Dictionary(uniqueKeysWithValues: beam.chordIDs.enumerated().map { ($0.element, $0.offset) })
            let segments = beam.segments.compactMap { segment -> GrandStaffNotationBeamSegment? in
                if let hookDirection = segment.hookDirection {
                    guard visibleChordIDs.contains(segment.startChordID) else { return nil }
                    return .init(
                        level: segment.level,
                        startChordID: segment.startChordID,
                        endChordID: segment.endChordID,
                        hookDirection: hookDirection
                    )
                }
                guard let startIndex = indexByChordID[segment.startChordID],
                      let endIndex = indexByChordID[segment.endChordID]
                else { return nil }
                let visible = beam.chordIDs[min(startIndex, endIndex) ... max(startIndex, endIndex)]
                    .filter { visibleChordIDs.contains($0) }
                guard let first = visible.first, let last = visible.last, first != last else { return nil }
                return .init(
                    level: segment.level,
                    startChordID: first,
                    endChordID: last,
                    hookDirection: nil
                )
            }
            guard segments.isEmpty == false else { return nil }
            let chordIDs = beam.chordIDs.filter { visibleChordIDs.contains($0) }
            return GrandStaffNotationBeam(id: beam.id, chordIDs: chordIDs, segments: segments)
        }
    }

    private func resolvedStaffNumber(_ staff: Int?) -> Int {
        guard let staff else { return 1 }
        return (staff >= 2) ? 2 : 1
    }

    private func buildChordsAndBeams(
        items: [GrandStaffNotationItem],
        notationFactsByOccurrenceID: [String: NotationFacts],
        measureSpans: [MusicXMLMeasureSpan],
        restBreaks: [RestBreak]
    ) -> (
        items: [GrandStaffNotationItem],
        chords: [GrandStaffNotationChord],
        beams: [GrandStaffNotationBeam],
        ledgerLines: [GrandStaffNotationLedgerLine]
    ) {
        guard items.isEmpty == false else { return (items, [], [], []) }

        let grouped = Dictionary(
            grouping: items,
            by: { item in
                ChordKey(performedSourceID: notationFactsByOccurrenceID[item.occurrenceID]?.chordID ?? item.occurrenceID)
            }
        )
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            let lhsTick = grouped[lhs]?.map(\.tick).min() ?? 0
            let rhsTick = grouped[rhs]?.map(\.tick).min() ?? 0
            if lhsTick != rhsTick { return lhsTick < rhsTick }
            return lhs.performedSourceID < rhs.performedSourceID
        }

        let candidates = sortedKeys.compactMap { key -> ChordCandidate? in
            guard let chordItems = grouped[key], chordItems.isEmpty == false else { return nil }
            return ChordCandidate(
                id: "chord-\(key.performedSourceID)",
                tick: chordItems.map(\.tick).min() ?? 0,
                xPosition: chordItems.map(\.xPosition).reduce(0.0, +) / Double(chordItems.count),
                items: chordItems,
                noteValue: resolvedChordNoteValue(items: chordItems)
            )
        }
        let chordGeometry = chordLayoutService.makeLayout(chords: candidates.map { candidate in
            GrandStaffChordLayoutService.Chord(
                id: candidate.id,
                tick: candidate.tick,
                xPosition: candidate.xPosition,
                notes: candidate.items.map { item in
                    GrandStaffChordLayoutService.Note(
                        id: item.occurrenceID,
                        staffNumber: item.staffNumber,
                        staffStep: item.staffStep,
                        voice: item.voice,
                        sourceStem: notationFactsByOccurrenceID[item.occurrenceID]?.stem ?? .unspecified,
                        noteheadToken: item.noteheadGlyphToken,
                        accidentalToken: item.displayedAccidental?.glyphToken,
                        dotCount: item.dotCount,
                        isGrace: item.isGrace,
                        ledgerStaffSteps: ledgerStaffSteps(for: item.staffStep)
                    )
                }
            )
        })
        let chordLayoutByID = Dictionary(uniqueKeysWithValues: chordGeometry.chords.map { ($0.chordID, $0) })
        var chords: [GrandStaffNotationChord] = []
        var updatedItemsByOccurrenceID: [String: GrandStaffNotationItem] = [:]
        updatedItemsByOccurrenceID.reserveCapacity(items.count)

        for candidate in candidates {
            guard let chordLayout = chordLayoutByID[candidate.id] else { continue }
            let stem = GrandStaffNotationStem(
                direction: chordLayout.direction,
                isVisible: chordLayout.isStemVisible,
                startItemID: chordLayout.stemStartItemID,
                endItemID: chordLayout.stemEndItemID,
                xOffset: chordLayout.stemXOffset
            )
            chords.append(GrandStaffNotationChord(
                id: candidate.id,
                tick: candidate.tick,
                xPosition: candidate.xPosition,
                itemIDs: candidate.items.map(\.occurrenceID),
                stem: stem,
                noteValue: candidate.noteValue
            ))

            for item in candidate.items {
                updatedItemsByOccurrenceID[item.occurrenceID] = GrandStaffNotationItem(
                    occurrenceID: item.occurrenceID,
                    staffNumber: item.staffNumber,
                    voice: item.voice,
                    hand: item.hand,
                    tick: item.tick,
                    xPosition: item.xPosition,
                    staffStep: item.staffStep,
                    displayedAccidental: item.displayedAccidental,
                    isHighlighted: item.isHighlighted,
                    fingerings: item.fingerings,
                    noteValue: item.noteValue,
                    chordID: candidate.id,
                    noteheadXOffset: chordLayout.noteheadXOffsets[item.occurrenceID] ?? 0,
                    accidentalXOffsetStaffSpaces: chordLayout.accidentalXOffsetsStaffSpaces[item.occurrenceID],
                    dotXOffsetStaffSpaces: chordLayout.dotLayouts[item.occurrenceID]?.xOffsetStaffSpaces,
                    dotStaffStep: chordLayout.dotLayouts[item.occurrenceID]?.staffStep,
                    beamID: nil,
                    durationTicks: item.durationTicks,
                    isGrace: item.isGrace,
                    articulations: item.articulations,
                    arpeggiate: item.arpeggiate,
                    dotCount: item.dotCount
                )
            }
        }

        let beamsBuild = buildBeams(
            chords: chords,
            itemsByOccurrenceID: updatedItemsByOccurrenceID,
            notationFactsByOccurrenceID: notationFactsByOccurrenceID,
            measureSpans: measureSpans,
            restBreaks: restBreaks
        )

        var beamIDByChordID: [String: String] = [:]
        for beamID in beamsBuild.beamChordIDsByBeamID.keys.sorted() {
            for chordID in beamsBuild.beamChordIDsByBeamID[beamID] ?? [] {
                beamIDByChordID[chordID] = beamID
            }
        }
        let normalizedItems = items.compactMap { original -> GrandStaffNotationItem? in
            guard let item = updatedItemsByOccurrenceID[original.occurrenceID] else { return nil }
            return GrandStaffNotationItem(
                occurrenceID: item.occurrenceID,
                staffNumber: item.staffNumber,
                voice: item.voice,
                hand: item.hand,
                tick: item.tick,
                xPosition: item.xPosition,
                staffStep: item.staffStep,
                displayedAccidental: item.displayedAccidental,
                isHighlighted: item.isHighlighted,
                fingerings: item.fingerings,
                noteValue: item.noteValue,
                chordID: item.chordID,
                noteheadXOffset: item.noteheadXOffset,
                accidentalXOffsetStaffSpaces: item.accidentalXOffsetStaffSpaces,
                dotXOffsetStaffSpaces: item.dotXOffsetStaffSpaces,
                dotStaffStep: item.dotStaffStep,
                beamID: item.chordID.flatMap { beamIDByChordID[$0] },
                durationTicks: item.durationTicks,
                isGrace: item.isGrace,
                articulations: item.articulations,
                arpeggiate: item.arpeggiate,
                dotCount: item.dotCount
            )
        }

        let ledgerLines = chordGeometry.ledgerLines.map {
            GrandStaffNotationLedgerLine(
                id: $0.id,
                tick: $0.tick,
                xPosition: $0.xPosition,
                staffNumber: $0.staffNumber,
                staffStep: $0.staffStep,
                minXOffsetStaffSpaces: $0.minXOffsetStaffSpaces,
                maxXOffsetStaffSpaces: $0.maxXOffsetStaffSpaces
            )
        }
        return (normalizedItems, chords, beamsBuild.beams, ledgerLines)
    }

    private func resolvedChordNoteValue(items: [GrandStaffNotationItem]) -> GrandStaffNoteValue {
        guard items.isEmpty == false else { return .quarter }
        return items.map(\.noteValue).min(by: { beamRank(for: $0) < beamRank(for: $1) }) ?? items[0].noteValue
    }

    private func beamRank(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
        case .unsupported:
            8
        case .oneHundredTwentyEighth:
            0
        case .sixtyFourth:
            1
        case .thirtySecond:
            2
        case .sixteenth:
            3
        case .eighth:
            4
        case .quarter:
            5
        case .half:
            6
        case .whole:
            7
        }
    }

    private func buildBeams(
        chords: [GrandStaffNotationChord],
        itemsByOccurrenceID: [String: GrandStaffNotationItem],
        notationFactsByOccurrenceID: [String: NotationFacts],
        measureSpans: [MusicXMLMeasureSpan],
        restBreaks: [RestBreak]
    ) -> (beams: [GrandStaffNotationBeam], beamChordIDsByBeamID: [String: [String]]) {
        if chords.isEmpty { return ([], [:]) }

        let chordsByID = Dictionary(uniqueKeysWithValues: chords.map { ($0.id, $0) })
        let membershipsByChordID = Dictionary(uniqueKeysWithValues: chords.map { chord in
            let memberships = chord.itemIDs.flatMap { notationFactsByOccurrenceID[$0]?.beams ?? [] }
            return (chord.id, memberships.reduce(into: [NotationFacts.BeamMembership]()) { result, membership in
                if result.contains(membership) == false { result.append(membership) }
            })
        })
        var explicitChordIDsByBeamID: [String: Set<String>] = [:]
        var chordsWithExplicitBeams: Set<String> = []
        for chord in chords {
            let memberships = membershipsByChordID[chord.id] ?? []
            guard memberships.isEmpty == false else { continue }
            chordsWithExplicitBeams.insert(chord.id)
            for membership in memberships where membership.level == 1 {
                explicitChordIDsByBeamID[membership.id, default: []].insert(chord.id)
            }
        }

        var beams: [GrandStaffNotationBeam] = []
        var beamChordIDsByBeamID: [String: [String]] = [:]
        for beamID in explicitChordIDsByBeamID.keys.sorted() {
            let chordIDs = sortedChordIDs(explicitChordIDsByBeamID[beamID] ?? [], chordsByID: chordsByID)
            let segments = explicitBeamSegments(
                chordIDs: chordIDs,
                membershipsByChordID: membershipsByChordID,
                chordsByID: chordsByID
            )
            guard segments.isEmpty == false else { continue }
            beamChordIDsByBeamID[beamID] = chordIDs
            beams.append(GrandStaffNotationBeam(
                id: beamID,
                chordIDs: chordIDs,
                segments: segments
            ))
        }

        var chordsByTrack: [String: [GrandStaffNotationChord]] = [:]
        for chord in chords {
            let track = chordTrackKey(chord: chord, itemsByOccurrenceID: itemsByOccurrenceID)
            chordsByTrack[track, default: []].append(chord)
        }

        for track in chordsByTrack.keys.sorted() {
            let trackChords = chordsByTrack[track] ?? []
            var currentGroup: [GrandStaffNotationChord] = []
            var currentCell: String?

            func flush() {
                guard currentGroup.count >= 2 else {
                    currentGroup.removeAll(keepingCapacity: true)
                    currentCell = nil
                    return
                }
                let beamID = "fallback-beam-\(track)-\(currentGroup[0].id)"
                let chordIDs = currentGroup.map(\.id)
                beamChordIDsByBeamID[beamID] = chordIDs
                beams.append(GrandStaffNotationBeam(
                    id: beamID,
                    chordIDs: chordIDs,
                    segments: fallbackBeamSegments(chords: currentGroup)
                ))
                currentGroup.removeAll(keepingCapacity: true)
                currentCell = nil
            }

            for chord in trackChords.sorted(by: { $0.tick == $1.tick ? $0.id < $1.id : $0.tick < $1.tick }) {
                guard chordsWithExplicitBeams.contains(chord.id) == false, beamCount(for: chord.noteValue) > 0 else {
                    flush()
                    continue
                }
                let cell = fallbackBeamCell(
                    chord: chord,
                    itemsByOccurrenceID: itemsByOccurrenceID,
                    notationFactsByOccurrenceID: notationFactsByOccurrenceID,
                    measureSpans: measureSpans
                )
                if currentCell != nil, currentCell != cell { flush() }
                if let previous = currentGroup.last,
                   let item = chord.itemIDs.compactMap({ itemsByOccurrenceID[$0] }).first,
                   restBreaks.contains(where: {
                       $0.staffNumber == item.staffNumber && $0.voice == item.voice &&
                           $0.tick > previous.tick && $0.tick <= chord.tick
                   }) {
                    flush()
                }

                currentGroup.append(chord)
                currentCell = cell
            }
            flush()
        }

        return (beams.sorted { $0.id < $1.id }, beamChordIDsByBeamID)
    }

    private func sortedChordIDs(
        _ chordIDs: Set<String>,
        chordsByID: [String: GrandStaffNotationChord]
    ) -> [String] {
        chordIDs.sorted { lhs, rhs in
            let lhsTick = chordsByID[lhs]?.tick ?? 0
            let rhsTick = chordsByID[rhs]?.tick ?? 0
            return lhsTick == rhsTick ? lhs < rhs : lhsTick < rhsTick
        }
    }

    private func explicitBeamSegments(
        chordIDs: [String],
        membershipsByChordID: [String: [NotationFacts.BeamMembership]],
        chordsByID: [String: GrandStaffNotationChord]
    ) -> [GrandStaffNotationBeamSegment] {
        let chordIDSet = Set(chordIDs)
        let memberships = chordIDs.flatMap { chordID in
            (membershipsByChordID[chordID] ?? []).map { (chordID, $0) }
        }
        var segments: [GrandStaffNotationBeamSegment] = []

        for level in Set(memberships.map { $0.1.level }).sorted() {
            let grouped = Dictionary(grouping: memberships.filter { $0.1.level == level }, by: { $0.1.id })
            for groupID in grouped.keys.sorted() {
                let entries = grouped[groupID] ?? []
                for (chordID, membership) in entries {
                    let hookDirection: GrandStaffNotationBeamSegment.HookDirection? = switch membership.value {
                    case .forwardHook: .forward
                    case .backwardHook: .backward
                    default: nil
                    }
                    if let hookDirection {
                        segments.append(.init(
                            level: level,
                            startChordID: chordID,
                            endChordID: chordID,
                            hookDirection: hookDirection
                        ))
                    }
                }
                let connectedIDs = Set(entries.compactMap { chordID, membership in
                    switch membership.value {
                    case .begin, .continue, .end: chordIDSet.contains(chordID) ? chordID : nil
                    default: nil
                    }
                })
                let sortedIDs = sortedChordIDs(connectedIDs, chordsByID: chordsByID)
                if let first = sortedIDs.first, let last = sortedIDs.last, first != last {
                    segments.append(.init(
                        level: level,
                        startChordID: first,
                        endChordID: last,
                        hookDirection: nil
                    ))
                }
            }
        }
        return segments.sorted {
            if $0.level != $1.level { return $0.level < $1.level }
            if $0.startChordID != $1.startChordID { return $0.startChordID < $1.startChordID }
            return $0.endChordID < $1.endChordID
        }
    }

    private func fallbackBeamSegments(chords: [GrandStaffNotationChord]) -> [GrandStaffNotationBeamSegment] {
        guard let first = chords.first, let last = chords.last, first.id != last.id else { return [] }
        var segments = [GrandStaffNotationBeamSegment(
            level: 1,
            startChordID: first.id,
            endChordID: last.id,
            hookDirection: nil
        )]
        let maximumLevel = chords.map(\.noteValue).map(beamCount(for:)).max() ?? 1
        guard maximumLevel >= 2 else { return segments }

        for level in 2 ... maximumLevel {
            var run: [GrandStaffNotationChord] = []
            func flushRun() {
                guard let runFirst = run.first, let runLast = run.last else { return }
                if runFirst.id == runLast.id {
                    let index = chords.firstIndex { $0.id == runFirst.id } ?? 0
                    segments.append(.init(
                        level: level,
                        startChordID: runFirst.id,
                        endChordID: runFirst.id,
                        hookDirection: index < chords.count - 1 ? .forward : .backward
                    ))
                } else {
                    segments.append(.init(
                        level: level,
                        startChordID: runFirst.id,
                        endChordID: runLast.id,
                        hookDirection: nil
                    ))
                }
                run.removeAll(keepingCapacity: true)
            }
            for chord in chords {
                if beamCount(for: chord.noteValue) >= level {
                    run.append(chord)
                } else {
                    flushRun()
                }
            }
            flushRun()
        }
        return segments
    }

    private func fallbackBeamCell(
        chord: GrandStaffNotationChord,
        itemsByOccurrenceID: [String: GrandStaffNotationItem],
        notationFactsByOccurrenceID: [String: NotationFacts],
        measureSpans: [MusicXMLMeasureSpan]
    ) -> String {
        let meter = chord.itemIDs.compactMap { notationFactsByOccurrenceID[$0]?.meter }.first
        let groupDurations = fallbackBeamGroupDurations(meter: meter)
        let measureDuration = max(1, groupDurations.reduce(0, +))
        let measureStart = measureSpans.first { $0.startTick <= chord.tick && chord.tick < $0.endTick }?.startTick
            ?? (chord.tick / measureDuration) * measureDuration
        let localTick = max(0, chord.tick - measureStart)
        var boundary = 0
        var groupIndex = 0
        for (index, duration) in groupDurations.enumerated() {
            boundary += duration
            if localTick < boundary {
                groupIndex = index
                break
            }
            groupIndex = index + 1
        }
        return "\(chordTrackKey(chord: chord, itemsByOccurrenceID: itemsByOccurrenceID))-\(measureStart)-\(groupIndex)"
    }

    private func fallbackBeamGroupDurations(meter: MusicXMLMeter?) -> [Int] {
        let components = meter?.components ?? [.init(beatGroups: [4], beatType: 4)]
        let durations = components.flatMap { component -> [Int] in
            let unit = max(1, MusicXMLTempoMap.ticksPerQuarter * 4 / max(1, component.beatType))
            if component.beatGroups.count > 1 {
                return component.beatGroups.map { max(1, $0) * unit }
            }
            let beats = max(1, component.beatGroups.first ?? 1)
            if component.beatType == 8, beats > 3, beats.isMultiple(of: 3) {
                return Array(repeating: 3 * unit, count: beats / 3)
            }
            return Array(repeating: unit, count: beats)
        }
        return durations.isEmpty ? [MusicXMLTempoMap.ticksPerQuarter] : durations
    }

    private func beamCount(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
        case .eighth:
            1
        case .sixteenth:
            2
        case .thirtySecond:
            3
        case .sixtyFourth:
            4
        case .oneHundredTwentyEighth:
            5
        default:
            0
        }
    }

    private func chordTrackKey(
        chord: GrandStaffNotationChord,
        itemsByOccurrenceID: [String: GrandStaffNotationItem]
    ) -> String {
        let items = chord.itemIDs.compactMap { itemsByOccurrenceID[$0] }
        let staff = items.map(\.staffNumber).min() ?? 1
        let voice = items.map(\.voice).min() ?? 1
        return "\(staff)-\(voice)"
    }

}
