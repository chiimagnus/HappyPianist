import Foundation

struct GrandStaffNotationLayoutService {
    private struct ChordKey: Hashable {
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
        let staffNumber: Int
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
        let key: SpannerKey
        let numberToken: String?
        let placementToken: String?
        let bracketToken: String?
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

    func makeLayout(
        projection: ScoreNotationProjection,
        overlay: ScoreNotationProjection.Overlay = .empty,
        measureSpans: [MusicXMLMeasureSpan] = [],
        context: GrandStaffNotationContext? = nil,
        halfWindowTicks: Int = 1920,
        scrollTick: Double? = nil
    ) -> GrandStaffNotationLayout {
        let sourceNotesByID = Dictionary(grouping: projection.sourceNotes, by: \.id)
            .compactMapValues { notes in notes.count == 1 ? notes[0] : nil }
        let occurrences = projection.performedOccurrences.enumerated().compactMap { index, occurrence -> LayoutOccurrence? in
            guard let source = sourceNotesByID[occurrence.sourceNoteID] else { return nil }
            return LayoutOccurrence(
                performedID: occurrence.id,
                occurrenceID: occurrence.id.description,
                source: source,
                staffNumber: resolvedStaffNumber(source.staff),
                voice: source.voice,
                hand: occurrence.handAssignment.hand,
                guideID: index + 1,
                tick: occurrence.writtenOnTick,
                isHighlighted: occurrence.performanceEventIDs.contains { overlay.activeEventIDs.contains($0) }
            )
        }
        let unresolvedNotes = occurrences.compactMap { occurrence -> LayoutNote? in
            let source = occurrence.source
            guard source.isRest == false,
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
                guideID: occurrence.guideID,
                tick: occurrence.tick,
                isHighlighted: occurrence.isHighlighted,
                fingeringText: source.fingeringText,
                noteValue: noteValue(for: source.writtenRhythm),
                durationTicks: writtenDurationTicks,
                writtenPitch: writtenPitch,
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
            activeTickRange: overlay.activeTickRange,
            measureSpans: measureSpans,
            context: context,
            halfWindowTicks: halfWindowTicks,
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
        let guideID: Int
        let tick: Int
        let isHighlighted: Bool
    }

    private struct LayoutNote {
        let performedID: MusicXMLPerformedNoteID
        let occurrenceID: String
        let staffNumber: Int
        let voice: Int
        let hand: ScoreHand
        let guideID: Int
        let tick: Int
        let isHighlighted: Bool
        let fingeringText: String?
        let noteValue: GrandStaffNoteValue
        let durationTicks: Int
        let writtenPitch: MusicXMLWrittenPitch
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
        activeTickRange: Range<Int>?,
        measureSpans: [MusicXMLMeasureSpan],
        context: GrandStaffNotationContext?,
        halfWindowTicks: Int,
        scrollTick: Double?
    ) -> GrandStaffNotationLayout {
        let currentTick = scrollTick ?? Double(occurrences.first?.tick ?? 0)
        let safeHalfWindowTicks = max(1, halfWindowTicks)
        let rawItems = notes.map { note in
            GrandStaffNotationItem(
                occurrenceID: note.occurrenceID,
                staffNumber: note.staffNumber,
                voice: note.voice,
                hand: note.hand,
                guideID: note.guideID,
                tick: note.tick,
                xPosition: 0.5 + (Double(note.tick) - currentTick) / Double(safeHalfWindowTicks * 2),
                staffStep: staffStep(for: note.writtenPitch, staffNumber: note.staffNumber),
                displayedAccidental: note.displayedAccidental,
                isHighlighted: note.isHighlighted,
                fingeringText: note.fingeringText,
                noteValue: note.noteValue,
                chordID: nil,
                noteHeadXOffset: 0,
                stemDirection: .up,
                beamID: nil,
                durationTicks: note.durationTicks,
                isGrace: note.isGrace,
                articulations: note.articulations,
                arpeggiate: note.arpeggiate,
                dotCount: note.dotCount
            )
        }
        .filter { item in
            (activeTickRange?.contains(item.tick) ?? true) &&
                item.xPosition >= -visibleOverscan && item.xPosition <= 1 + visibleOverscan
        }
        .sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
            if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
            if lhs.staffStep != rhs.staffStep { return lhs.staffStep < rhs.staffStep }
            return lhs.occurrenceID < rhs.occurrenceID
        }

        let chordBuild = buildChordsAndBeams(items: rawItems, measureSpans: measureSpans)
        let rests = occurrences.compactMap { occurrence -> GrandStaffNotationRest? in
            let source = occurrence.source
            guard source.isRest, source.isPrintObjectVisible,
                  activeTickRange?.contains(occurrence.tick) ?? true
            else { return nil }
            let xPosition = xPosition(
                for: occurrence.tick,
                currentTick: currentTick,
                safeHalfWindowTicks: safeHalfWindowTicks
            )
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return GrandStaffNotationRest(
                id: occurrence.occurrenceID,
                staffNumber: occurrence.staffNumber,
                voice: occurrence.voice,
                guideID: occurrence.guideID,
                tick: occurrence.tick,
                xPosition: xPosition,
                noteValue: noteValue(for: source.writtenRhythm),
                dotCount: source.writtenRhythm?.dotCount ?? 0,
                isHighlighted: occurrence.isHighlighted
            )
        }
        let spanners = clippedSpannerSegments(
            occurrences: occurrences,
            activeTickRange: activeTickRange,
            currentTick: currentTick,
            safeHalfWindowTicks: safeHalfWindowTicks
        )

        let barlines = makeBarlines(
            measureSpans: measureSpans,
            currentTick: currentTick,
            safeHalfWindowTicks: safeHalfWindowTicks
        )

        return GrandStaffNotationLayout(
            items: chordBuild.items,
            chords: chordBuild.chords,
            rests: rests,
            ties: spanners.compactMap(makeTie),
            slurs: spanners.compactMap(makeSlur),
            tuplets: spanners.compactMap(makeTuplet),
            barlines: barlines,
            beams: chordBuild.beams,
            context: context
        )
    }

    private func clippedSpannerSegments(
        occurrences: [LayoutOccurrence],
        activeTickRange: Range<Int>?,
        currentTick: Double,
        safeHalfWindowTicks: Int
    ) -> [ClippedSpannerSegment] {
        let tickWidth = Double(safeHalfWindowTicks * 2)
        let viewportLower = Int(floor(currentTick + (-visibleOverscan - 0.5) * tickWidth))
        let viewportUpper = Int(ceil(currentTick + (1 + visibleOverscan - 0.5) * tickWidth))
        let lowerTick = max(viewportLower, activeTickRange?.lowerBound ?? viewportLower)
        let upperTick = min(viewportUpper, activeTickRange?.upperBound ?? viewportUpper)
        guard lowerTick < upperTick else { return [] }

        return pairedSpannerSegments(occurrences: occurrences).compactMap { segment in
            let startTick = segment.start?.tick
            let endTick = segment.end?.tick
            guard (startTick ?? Int.min) < upperTick, (endTick ?? Int.max) >= lowerTick else {
                return nil
            }
            let continuesFromPrevious = startTick == nil || startTick! < lowerTick
            let continuesToNext = endTick == nil || endTick! >= upperTick
            let clippedStartTick = max(startTick ?? lowerTick, lowerTick)
            let clippedEndTick = min(endTick ?? upperTick, upperTick)
            guard clippedStartTick <= clippedEndTick else { return nil }
            return ClippedSpannerSegment(
                segment: segment,
                startXPosition: xPosition(
                    for: clippedStartTick,
                    currentTick: currentTick,
                    safeHalfWindowTicks: safeHalfWindowTicks
                ),
                endXPosition: xPosition(
                    for: clippedEndTick,
                    currentTick: currentTick,
                    safeHalfWindowTicks: safeHalfWindowTicks
                ),
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
            key: SpannerKey(
                kind: kind,
                partID: occurrence.performedID.sourceID.partID,
                staffNumber: occurrence.staffNumber,
                voice: occurrence.voice,
                numberToken: normalizedNumber,
                pitchStep: writtenPitch?.step,
                pitchOctave: writtenPitch?.octave,
                pitchAlter: writtenPitch?.alter
            ),
            numberToken: numberToken,
            placementToken: placementToken,
            bracketToken: bracketToken,
            typeToken: typeToken
        )
    }

    private func makeTie(_ clipped: ClippedSpannerSegment) -> GrandStaffNotationTie? {
        guard clipped.segment.kind == .tie, let endpoint = clipped.segment.start ?? clipped.segment.end else { return nil }
        return GrandStaffNotationTie(
            id: spannerID(clipped.segment),
            staffNumber: endpoint.key.staffNumber,
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
            staffNumber: endpoint.key.staffNumber,
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
            staffNumber: endpoint.key.staffNumber,
            voice: endpoint.key.voice,
            numberToken: clipped.segment.start?.numberToken ?? clipped.segment.end?.numberToken,
            bracketToken: clipped.segment.start?.bracketToken ?? clipped.segment.end?.bracketToken,
            placementToken: clipped.segment.start?.placementToken ?? clipped.segment.end?.placementToken,
            startOccurrenceID: clipped.continuesFromPrevious ? nil : clipped.segment.start?.occurrenceID,
            endOccurrenceID: clipped.continuesToNext ? nil : clipped.segment.end?.occurrenceID,
            startXPosition: clipped.startXPosition,
            endXPosition: clipped.endXPosition,
            continuesFromPrevious: clipped.continuesFromPrevious,
            continuesToNext: clipped.continuesToNext
        )
    }

    private func spannerID(_ segment: SpannerSegment) -> String {
        "\(segment.kind.rawValue):\(segment.start?.id ?? "boundary"):\(segment.end?.id ?? "boundary")"
    }

    private func normalizedSpannerNumber(_ numberToken: String?) -> String {
        let trimmed = numberToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "1" : trimmed
    }

    private func xPosition(for tick: Int, currentTick: Double, safeHalfWindowTicks: Int) -> Double {
        0.5 + (Double(tick) - currentTick) / Double(safeHalfWindowTicks * 2)
    }

    func staffStep(for writtenPitch: MusicXMLWrittenPitch, staffNumber: Int) -> Int {
        let bottomLineIndex = staffNumber >= 2
            ? writtenDiatonicIndex(step: "G", octave: 2)
            : writtenDiatonicIndex(step: "E", octave: 4)
        return writtenDiatonicIndex(step: writtenPitch.step, octave: writtenPitch.octave) - bottomLineIndex
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

    func ledgerStaffSteps(for staffStep: Int) -> [Int] {
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

    private func noteValue(for rhythm: MusicXMLWrittenRhythm?) -> GrandStaffNoteValue {
        let sourceTypeToken = rhythm?.typeToken
        return switch sourceTypeToken?.lowercased() {
        case "whole": .whole
        case "half": .half
        case "quarter": .quarter
        case "eighth": .eighth
        case "16th": .sixteenth
        case "32nd": .thirtySecond
        default: .unsupported(sourceTypeToken: sourceTypeToken)
        }
    }

    private func makeBarlines(
        measureSpans: [MusicXMLMeasureSpan],
        currentTick: Double,
        safeHalfWindowTicks: Int
    ) -> [GrandStaffNotationBarline] {
        var ticks = Set(measureSpans.map(\.startTick))
        if let lastEnd = measureSpans.map(\.endTick).max() {
            ticks.insert(lastEnd)
        }

        return ticks.sorted().compactMap { tick in
            let xPosition = 0.5 + (Double(tick) - currentTick) / Double(safeHalfWindowTicks * 2)
            guard xPosition >= -visibleOverscan, xPosition <= 1 + visibleOverscan else { return nil }
            return GrandStaffNotationBarline(id: "barline-\(tick)", tick: tick, xPosition: xPosition)
        }
    }

    private func resolvedStaffNumber(_ staff: Int?) -> Int {
        guard let staff else { return 1 }
        return (staff >= 2) ? 2 : 1
    }

    private func buildChordsAndBeams(
        items: [GrandStaffNotationItem],
        measureSpans: [MusicXMLMeasureSpan]
    ) -> (items: [GrandStaffNotationItem], chords: [GrandStaffNotationChord], beams: [GrandStaffNotationBeam]) {
        guard items.isEmpty == false else { return (items, [], []) }

        let barlineTicks = Set(measureSpans.map(\.startTick))
            .union([measureSpans.map(\.endTick).max()].compactMap(\.self))

        let grouped = Dictionary(
            grouping: items,
            by: { ChordKey(tick: $0.tick, staffNumber: $0.staffNumber, voice: $0.voice) }
        )
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
            return lhs.voice < rhs.voice
        }

        var chords: [GrandStaffNotationChord] = []
        chords.reserveCapacity(sortedKeys.count)

        var updatedItemsByOccurrenceID: [String: GrandStaffNotationItem] = [:]
        updatedItemsByOccurrenceID.reserveCapacity(items.count)

        for key in sortedKeys {
            guard let chordItems = grouped[key], chordItems.isEmpty == false else { continue }

            let chordID = "chord-\(key.tick)-\(key.staffNumber)-\(key.voice)"
            let xPosition = chordItems.map(\.xPosition).reduce(0.0, +) / Double(chordItems.count)
            let stemDirection = resolvedStemDirection(chordItems: chordItems)
            let noteValue = resolvedChordNoteValue(items: chordItems)

            chords.append(GrandStaffNotationChord(
                id: chordID,
                tick: key.tick,
                xPosition: xPosition,
                itemIDs: chordItems.map(\.occurrenceID),
                stemDirection: stemDirection,
                noteValue: noteValue
            ))

            for item in chordItems {
                updatedItemsByOccurrenceID[item.occurrenceID] = GrandStaffNotationItem(
                    occurrenceID: item.occurrenceID,
                    staffNumber: item.staffNumber,
                    voice: item.voice,
                    hand: item.hand,
                    guideID: item.guideID,
                    tick: item.tick,
                    xPosition: item.xPosition,
                    staffStep: item.staffStep,
                    displayedAccidental: item.displayedAccidental,
                    isHighlighted: item.isHighlighted,
                    fingeringText: item.fingeringText,
                    noteValue: item.noteValue,
                    chordID: chordID,
                    noteHeadXOffset: item.noteHeadXOffset,
                    stemDirection: stemDirection,
                    beamID: nil,
                    durationTicks: item.durationTicks,
                    isGrace: item.isGrace,
                    articulations: item.articulations,
                    arpeggiate: item.arpeggiate,
                    dotCount: item.dotCount
                )
            }
        }

        _ = items.compactMap { updatedItemsByOccurrenceID[$0.occurrenceID] }

        let beamsBuild = buildBeams(
            chords: chords,
            barlineTicks: barlineTicks
        )

        var beamedItemsByOccurrenceID = updatedItemsByOccurrenceID
        for (beamID, chordIDs) in beamsBuild.beamChordIDsByBeamID {
            for chordID in chordIDs {
                guard let chord = chords.first(where: { $0.id == chordID }) else { continue }
                for itemID in chord.itemIDs {
                    if let existing = beamedItemsByOccurrenceID[itemID] {
                        beamedItemsByOccurrenceID[itemID] = GrandStaffNotationItem(
                            occurrenceID: existing.occurrenceID,
                            staffNumber: existing.staffNumber,
                            voice: existing.voice,
                            hand: existing.hand,
                            guideID: existing.guideID,
                            tick: existing.tick,
                            xPosition: existing.xPosition,
                            staffStep: existing.staffStep,
                            displayedAccidental: existing.displayedAccidental,
                            isHighlighted: existing.isHighlighted,
                            fingeringText: existing.fingeringText,
                            noteValue: existing.noteValue,
                            chordID: existing.chordID,
                            noteHeadXOffset: existing.noteHeadXOffset,
                            stemDirection: existing.stemDirection,
                            beamID: beamID,
                            durationTicks: existing.durationTicks,
                            isGrace: existing.isGrace,
                            articulations: existing.articulations,
                            arpeggiate: existing.arpeggiate,
                            dotCount: existing.dotCount
                        )
                    }
                }
            }
        }

        _ = items.compactMap { beamedItemsByOccurrenceID[$0.occurrenceID] }

        let finalChords = enforceBeamGroupStemDirections(
            chords: chords,
            itemsByOccurrenceID: beamedItemsByOccurrenceID,
            beamChordIDsByBeamID: beamsBuild.beamChordIDsByBeamID
        )
        var finalItemsByOccurrenceID = beamedItemsByOccurrenceID
        for chord in finalChords {
            for itemID in chord.itemIDs {
                if let existing = finalItemsByOccurrenceID[itemID] {
                    finalItemsByOccurrenceID[itemID] = GrandStaffNotationItem(
                        occurrenceID: existing.occurrenceID,
                        staffNumber: existing.staffNumber,
                        voice: existing.voice,
                        hand: existing.hand,
                        guideID: existing.guideID,
                        tick: existing.tick,
                        xPosition: existing.xPosition,
                        staffStep: existing.staffStep,
                        displayedAccidental: existing.displayedAccidental,
                        isHighlighted: existing.isHighlighted,
                        fingeringText: existing.fingeringText,
                        noteValue: existing.noteValue,
                        chordID: existing.chordID,
                        noteHeadXOffset: existing.noteHeadXOffset,
                        stemDirection: chord.stemDirection,
                        beamID: existing.beamID,
                        durationTicks: existing.durationTicks,
                        isGrace: existing.isGrace,
                        articulations: existing.articulations,
                        arpeggiate: existing.arpeggiate,
                        dotCount: existing.dotCount
                    )
                }
            }
        }

        let normalizedItems = items.compactMap { finalItemsByOccurrenceID[$0.occurrenceID] }

        return (normalizedItems, finalChords, beamsBuild.beams)
    }

    private func resolvedStemDirection(chordItems: [GrandStaffNotationItem]) -> GrandStaffStemDirection {
        if chordItems.contains(where: { $0.hand == .left }) {
            return .down
        }
        return .up
    }

    private func resolvedChordNoteValue(items: [GrandStaffNotationItem]) -> GrandStaffNoteValue {
        guard items.isEmpty == false else { return .quarter }
        return items.map(\.noteValue).min(by: { beamRank(for: $0) < beamRank(for: $1) }) ?? items[0].noteValue
    }

    private func beamRank(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
        case .unsupported:
            6
        case .thirtySecond:
            0
        case .sixteenth:
            1
        case .eighth:
            2
        case .quarter:
            3
        case .half:
            4
        case .whole:
            5
        }
    }

    private func buildBeams(
        chords: [GrandStaffNotationChord],
        barlineTicks: Set<Int>
    ) -> (beams: [GrandStaffNotationBeam], beamChordIDsByBeamID: [String: [String]]) {
        if chords.isEmpty { return ([], [:]) }

        let eligible = chords
            .filter { $0.noteValue == .eighth || $0.noteValue == .sixteenth || $0.noteValue == .thirtySecond }
            .sorted { lhs, rhs in
                if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
                return lhs.id < rhs.id
            }

        var chordsByTrack: [String: [GrandStaffNotationChord]] = [:]
        for chord in eligible {
            let track = chordTrackKey(chordID: chord.id)
            chordsByTrack[track, default: []].append(chord)
        }

        var beams: [GrandStaffNotationBeam] = []
        var beamChordIDsByBeamID: [String: [String]] = [:]
        var beamCounter = 0

        for (_, trackChords) in chordsByTrack {
            var currentGroup: [GrandStaffNotationChord] = []
            var lastTick: Int?

            func flush() {
                guard currentGroup.count >= 2 else {
                    currentGroup.removeAll(keepingCapacity: true)
                    return
                }
                beamCounter += 1
                let beamID = "beam-\(beamCounter)"
                let chordIDs = currentGroup.map(\.id)
                beamChordIDsByBeamID[beamID] = chordIDs
                let maxBeamCount = currentGroup.map(\.noteValue).map(beamCount(for:)).max() ?? 1
                beams.append(GrandStaffNotationBeam(id: beamID, chordIDs: chordIDs, beamCount: max(1, maxBeamCount)))
                currentGroup.removeAll(keepingCapacity: true)
                lastTick = nil
            }

            for chord in trackChords.sorted(by: { $0.tick < $1.tick }) {
                if barlineTicks.contains(chord.tick), currentGroup.isEmpty == false {
                    flush()
                }

                if let lastTick {
                    let delta = chord.tick - lastTick
                    if delta > MusicXMLTempoMap.ticksPerQuarter {
                        flush()
                    }
                }

                currentGroup.append(chord)
                lastTick = chord.tick
            }
            flush()
        }

        return (beams, beamChordIDsByBeamID)
    }

    private func enforceBeamGroupStemDirections(
        chords: [GrandStaffNotationChord],
        itemsByOccurrenceID: [String: GrandStaffNotationItem],
        beamChordIDsByBeamID: [String: [String]]
    ) -> [GrandStaffNotationChord] {
        guard beamChordIDsByBeamID.isEmpty == false else { return chords }

        var overrideByChordID: [String: GrandStaffStemDirection] = [:]

        for chordIDs in beamChordIDsByBeamID.values {
            var hasLeftHand = false
            var hasRightHand = false

            for chordID in chordIDs {
                guard let chord = chords.first(where: { $0.id == chordID }) else { continue }
                for itemID in chord.itemIDs {
                    guard let item = itemsByOccurrenceID[itemID] else { continue }
                    if item.hand == .left { hasLeftHand = true } else { hasRightHand = true }
                }
            }

            let direction: GrandStaffStemDirection
            if hasLeftHand, hasRightHand == false {
                direction = .down
            } else if hasRightHand, hasLeftHand == false {
                direction = .up
            } else {
                // Mixed fallback: prefer staff number encoded in chordID (chord-<tick>-<staff>-<voice>)
                let staffToken = chordIDs.first?.split(separator: "-").dropFirst(2).first
                if let staffToken, let staff = Int(staffToken), staff >= 2 {
                    direction = .down
                } else {
                    direction = .up
                }
            }

            for chordID in chordIDs {
                overrideByChordID[chordID] = direction
            }
        }

        return chords.map { chord in
            if let forced = overrideByChordID[chord.id], forced != chord.stemDirection {
                return GrandStaffNotationChord(
                    id: chord.id,
                    tick: chord.tick,
                    xPosition: chord.xPosition,
                    itemIDs: chord.itemIDs,
                    stemDirection: forced,
                    noteValue: chord.noteValue
                )
            }
            return chord
        }
    }

    private func beamCount(for noteValue: GrandStaffNoteValue) -> Int {
        switch noteValue {
        case .eighth:
            1
        case .sixteenth:
            2
        case .thirtySecond:
            3
        default:
            0
        }
    }

    private func chordTrackKey(chordID: String) -> String {
        // chord-<tick>-<staff>-<voice>
        let parts = chordID.split(separator: "-")
        guard parts.count >= 4 else { return chordID }
        let staff = parts[2]
        let voice = parts[3]
        return "\(staff)-\(voice)"
    }

}
