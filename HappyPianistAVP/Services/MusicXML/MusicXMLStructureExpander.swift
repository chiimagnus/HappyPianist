import Foundation

struct MusicXMLStructureExpander {
    private let maxOutputMeasures: Int
    private let maxJumps: Int

    init(maxOutputMeasures: Int = 10000, maxJumps: Int = 64) {
        self.maxOutputMeasures = max(0, maxOutputMeasures)
        self.maxJumps = max(0, maxJumps)
    }

    func expandStructureIfPossible(
        score: MusicXMLScore,
        primaryPartID: String = "P1",
        includedPartIDs: Set<String>? = nil
    ) -> MusicXMLStructureExpansionResult {
        let repeatResult = expandRepeatAndEnding(
            score: score,
            primaryPartID: primaryPartID,
            includedPartIDs: includedPartIDs
        )
        guard repeatResult.approximationReason == nil else { return repeatResult }

        let result = expandSoundJumpsIfPossible(
            score: repeatResult.score,
            primaryPartID: primaryPartID,
            includedPartIDs: includedPartIDs
        )
        guard result.approximationReason == nil else {
            return MusicXMLStructureExpansionResult(
                score: score,
                approximationReason: result.approximationReason
            )
        }
        return result
    }

    func expandRepeatAndEndingIfPossible(
        score: MusicXMLScore,
        primaryPartID: String = "P1",
        includedPartIDs: Set<String>? = nil
    ) -> MusicXMLScore {
        expandRepeatAndEnding(
            score: score,
            primaryPartID: primaryPartID,
            includedPartIDs: includedPartIDs
        ).score
    }

    private func expandRepeatAndEnding(
        score: MusicXMLScore,
        primaryPartID: String,
        includedPartIDs: Set<String>?
    ) -> MusicXMLStructureExpansionResult {
        let repeats = score.repeatDirectives.filter { $0.partID == primaryPartID }
        let endings = score.endingDirectives.filter { $0.partID == primaryPartID }
        guard repeats.isEmpty == false || endings.isEmpty == false else {
            return MusicXMLStructureExpansionResult(score: score, approximationReason: nil)
        }

        let primaryMeasures = score.measures
            .filter { $0.partID == primaryPartID }
            .sorted { $0.startTick < $1.startTick }

        guard primaryMeasures.isEmpty == false else {
            return repeatExpansionFallback(score: score, reason: "structure-expansion-invalid-repeat-ending")
        }

        var measureIndexByNumber: [Int: Int] = [:]
        for (index, span) in primaryMeasures.enumerated() {
            if measureIndexByNumber[span.measureNumber] == nil {
                measureIndexByNumber[span.measureNumber] = index
            }
        }

        let indexedRepeats = repeats.compactMap { directive -> (Int, MusicXMLRepeatDirective)? in
            guard let index = measureIndexByNumber[directive.measureNumber] else { return nil }
            return (index, directive)
        }
        guard indexedRepeats.count == repeats.count,
              let endingSpans = resolveEndingSpans(
            directives: endings,
            measureIndexByNumber: measureIndexByNumber
        ) else {
            return repeatExpansionFallback(score: score, reason: "structure-expansion-invalid-repeat-ending")
        }

        let directivesByMeasure = Dictionary(grouping: indexedRepeats, by: \.0)
            .mapValues { $0.map(\.1) }
        let expansion = repeatSequence(
            measureCount: primaryMeasures.count,
            directivesByMeasure: directivesByMeasure,
            endingSpans: endingSpans
        )
        guard let sequence = expansion.sequence else {
            return repeatExpansionFallback(
                score: score,
                reason: expansion.approximationReason ?? "structure-expansion-invalid-repeat-ending"
            )
        }

        return MusicXMLStructureExpansionResult(
            score: materializeExpandedScore(
                original: score,
                primaryPartID: primaryPartID,
                primaryMeasures: primaryMeasures,
                sequence: sequence,
                includeSoundDirectives: true,
                includedPartIDs: includedPartIDs
            ),
            approximationReason: nil
        )
    }

    private struct MeasureVisit {
        let index: Int
        let repeatPass: Int?
    }

    private struct RepeatFrame {
        let startIndex: Int
        var pass: Int
        var totalPasses: Int?
    }

    private struct RepeatSequenceResult {
        let sequence: [MeasureVisit]?
        let approximationReason: String?
    }

    private func repeatSequence(
        measureCount: Int,
        directivesByMeasure: [Int: [MusicXMLRepeatDirective]],
        endingSpans: [EndingSpan]
    ) -> RepeatSequenceResult {
        guard directivesByMeasure.isEmpty == false else {
            return RepeatSequenceResult(
                sequence: nil,
                approximationReason: "structure-expansion-invalid-repeat-ending"
            )
        }

        var endingPassesByMeasure: [Int: Set<Int>] = [:]
        for span in endingSpans {
            for index in span.startIndex ... span.endIndex {
                endingPassesByMeasure[index, default: []].formUnion(span.passes)
            }
        }

        var sequence: [MeasureVisit] = []
        var frames: [RepeatFrame] = []
        var currentIndex = 0
        var implicitRepeatStart = 0
        var trailingCompletedPass: Int?
        var transitionCount = 0
        let transitionLimit = max(1024, min(maxOutputMeasures, 100_000) * 4 + min(measureCount, 100_000) * 4)

        while currentIndex < measureCount {
            transitionCount += 1
            guard transitionCount <= transitionLimit else {
                return RepeatSequenceResult(
                    sequence: nil,
                    approximationReason: "structure-expansion-output-measure-limit"
                )
            }

            let directives = directivesByMeasure[currentIndex] ?? []
            let forwards = directives.filter { $0.direction == .forward }
            let backwards = directives.filter { $0.direction == .backward }
            guard forwards.count <= 1, backwards.count <= 1 else {
                return RepeatSequenceResult(
                    sequence: nil,
                    approximationReason: "structure-expansion-invalid-repeat-ending"
                )
            }

            if forwards.isEmpty == false {
                if let activeIndex = frames.lastIndex(where: { $0.startIndex == currentIndex }) {
                    guard activeIndex == frames.indices.last else {
                        return RepeatSequenceResult(
                            sequence: nil,
                            approximationReason: "structure-expansion-invalid-repeat-ending"
                        )
                    }
                } else {
                    frames.append(RepeatFrame(startIndex: currentIndex, pass: 1, totalPasses: nil))
                }
            }

            let endingPasses = endingPassesByMeasure[currentIndex]
            if endingPasses == nil, frames.isEmpty {
                trailingCompletedPass = nil
            }
            let currentPass = frames.last?.pass ?? trailingCompletedPass ?? 1
            if endingPasses?.contains(currentPass) != false {
                guard sequence.count < maxOutputMeasures else {
                    return RepeatSequenceResult(
                        sequence: nil,
                        approximationReason: "structure-expansion-output-measure-limit"
                    )
                }
                sequence.append(MeasureVisit(index: currentIndex, repeatPass: currentPass))
            }

            guard let backward = backwards.first else {
                currentIndex += 1
                continue
            }

            if frames.isEmpty {
                frames.append(RepeatFrame(startIndex: implicitRepeatStart, pass: 1, totalPasses: nil))
            }
            guard var frame = frames.popLast(), frame.startIndex <= currentIndex else {
                return RepeatSequenceResult(
                    sequence: nil,
                    approximationReason: "structure-expansion-invalid-repeat-ending"
                )
            }

            let totalPasses = max(1, backward.times ?? frame.totalPasses ?? 2)
            if let configuredTotal = frame.totalPasses, configuredTotal != totalPasses {
                return RepeatSequenceResult(
                    sequence: nil,
                    approximationReason: "structure-expansion-invalid-repeat-ending"
                )
            }
            frame.totalPasses = totalPasses

            if frame.pass < totalPasses {
                frame.pass += 1
                frames.append(frame)
                trailingCompletedPass = nil
                currentIndex = frame.startIndex
            } else {
                if frames.isEmpty {
                    implicitRepeatStart = currentIndex + 1
                    trailingCompletedPass = frame.pass
                }
                currentIndex += 1
            }
        }

        guard frames.isEmpty else {
            return RepeatSequenceResult(
                sequence: nil,
                approximationReason: "structure-expansion-invalid-repeat-ending"
            )
        }
        return RepeatSequenceResult(sequence: sequence, approximationReason: nil)
    }

    private struct EndingSpan {
        let startIndex: Int
        let endIndex: Int
        let passes: Set<Int>
    }

    private func resolveEndingSpans(
        directives: [MusicXMLEndingDirective],
        measureIndexByNumber: [Int: Int]
    ) -> [EndingSpan]? {
        let indexedDirectives = directives.enumerated().compactMap { sourceIndex, directive -> (Int, Int, MusicXMLEndingDirective)? in
            guard let index = measureIndexByNumber[directive.measureNumber] else { return nil }
            return (index, sourceIndex, directive)
        }
        .sorted { lhs, rhs in
            lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }
        guard indexedDirectives.count == directives.count else { return nil }

        var activeStartByPass: [Int: Int] = [:]
        var spans: [EndingSpan] = []

        for (measureIndex, _, directive) in indexedDirectives {
            let passes = Set(directive.number
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap(Int.init)
                .filter { $0 > 0 })
            guard passes.isEmpty == false else { return nil }

            if directive.type == .start {
                for pass in passes {
                    guard activeStartByPass[pass] == nil else { return nil }
                    activeStartByPass[pass] = measureIndex
                }
                continue
            }

            if directive.type == .stop || directive.type == .discontinue {
                for pass in passes {
                    guard let start = activeStartByPass.removeValue(forKey: pass), start <= measureIndex else {
                        return nil
                    }
                    spans.append(EndingSpan(startIndex: start, endIndex: measureIndex, passes: [pass]))
                }
            }
        }

        guard activeStartByPass.isEmpty else { return nil }
        return spans
    }

    private func repeatExpansionFallback(score: MusicXMLScore, reason: String) -> MusicXMLStructureExpansionResult {
        MusicXMLStructureExpansionResult(score: score, approximationReason: reason)
    }

    private func materializeExpandedScore(
        original: MusicXMLScore,
        primaryPartID: String,
        primaryMeasures: [MusicXMLMeasureSpan],
        sequence: [MeasureVisit],
        includeSoundDirectives: Bool,
        includedPartIDs: Set<String>?
    ) -> MusicXMLScore {
        let selectedPartIDs = includedPartIDs ?? [primaryPartID]
        var outputNotes: [MusicXMLNoteEvent] = []
        var outputTempoEvents: [MusicXMLTempoEvent] = []
        var outputSoundDirectives: [MusicXMLSoundDirective] = []
        var outputPedalEvents: [MusicXMLPedalEvent] = []
        var outputDynamicEvents: [MusicXMLDynamicEvent] = []
        var outputWedgeEvents: [MusicXMLWedgeEvent] = []
        var outputFermataEvents: [MusicXMLFermataEvent] = []
        var outputTimeSignatureEvents: [MusicXMLTimeSignatureEvent] = []
        var outputKeySignatureEvents: [MusicXMLKeySignatureEvent] = []
        var outputClefEvents: [MusicXMLClefEvent] = []
        var outputTransposeEvents: [MusicXMLTransposeEvent] = []
        var outputOctaveShiftEvents: [MusicXMLOctaveShiftEvent] = []
        var outputWordsEvents: [MusicXMLWordsEvent] = []
        var outputMeasures: [MusicXMLMeasureSpan] = []

        outputNotes.reserveCapacity(original.notes.count)
        outputTempoEvents.reserveCapacity(original.tempoEvents.count)
        outputSoundDirectives.reserveCapacity(original.soundDirectives.count)
        outputPedalEvents.reserveCapacity(original.pedalEvents.count)
        outputDynamicEvents.reserveCapacity(original.dynamicEvents.count)
        outputWedgeEvents.reserveCapacity(original.wedgeEvents.count)
        outputFermataEvents.reserveCapacity(original.fermataEvents.count)
        outputTimeSignatureEvents.reserveCapacity(original.timeSignatureEvents.count)
        outputKeySignatureEvents.reserveCapacity(original.keySignatureEvents.count)
        outputClefEvents.reserveCapacity(original.clefEvents.count)
        outputTransposeEvents.reserveCapacity(original.transposeEvents.count)
        outputOctaveShiftEvents.reserveCapacity(original.octaveShiftEvents.count)
        outputWordsEvents.reserveCapacity(original.wordsEvents.count)
        outputMeasures.reserveCapacity(sequence.count * selectedPartIDs.count)

        let orderedSelectedPartIDs = orderedPartIDs(
            selectedPartIDs,
            partMetadata: original.partMetadata
        )
        var outputTick = 0
        var outputMeasureNumber = 1
        var passBySourceMeasureID: [PracticeSourceMeasureID: Int] = [:]

        for (occurrenceIndex, visit) in sequence.enumerated() {
            let index = visit.index
            guard primaryMeasures.indices.contains(index) else { continue }
            let span = primaryMeasures[index]
            let duration = max(0, span.endTick - span.startTick)
            let currentMeasureStartTick = outputTick
            let sourceMeasureID = span.sourceMeasureID
            let sourceOccurrencePass = (passBySourceMeasureID[sourceMeasureID] ?? 0) + 1
            passBySourceMeasureID[sourceMeasureID] = sourceOccurrencePass
            let pass = visit.repeatPass ?? sourceOccurrencePass

            let notesInMeasure = original.notes.filter { note in
                selectedPartIDs.contains(note.partID) && note.tick >= span.startTick && note.tick < span.endTick
            }
            for note in notesInMeasure {
                let shiftedTick = currentMeasureStartTick + (note.tick - span.startTick)
                outputNotes.append(
                    MusicXMLNoteEvent(
                        sourceID: note.sourceID,
                        performedOccurrenceIndex: occurrenceIndex,
                        partID: note.partID,
                        measureNumber: outputMeasureNumber,
                        tick: shiftedTick,
                        durationTicks: note.durationTicks,
                        writtenPitch: note.writtenPitch,
                        writtenRhythm: note.writtenRhythm,
                        midiNote: note.midiNote,
                        isRest: note.isRest,
                        isChord: note.isChord,
                        isGrace: note.isGrace,
                        graceSlash: note.graceSlash,
                        graceStealTimePrevious: note.graceStealTimePrevious,
                        graceStealTimeFollowing: note.graceStealTimeFollowing,
                        graceMakeTimeTicks: note.graceMakeTimeTicks,
                        tieStart: note.tieStart,
                        tieStop: note.tieStop,
                        staff: note.staff,
                        voice: note.voice,
                        attackTicks: note.attackTicks,
                        releaseTicks: note.releaseTicks,
                        dynamicsOverrideVelocity: note.dynamicsOverrideVelocity,
                        articulations: note.articulations,
                        arpeggiate: note.arpeggiate,
                        performanceNotations: note.performanceNotations,
                        fingeringText: note.fingeringText
                    )
                )
            }

            for event in original.tempoEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputTempoEvents.append(MusicXMLTempoEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    quarterBPM: event.quarterBPM,
                    scope: shiftedScope(event.scope)
                ))
            }

            if includeSoundDirectives {
                let soundsInMeasure = original.soundDirectives.filter { event in
                    selectedPartIDs.contains(event.partID) && event.measureNumber == span.measureNumber
                }
                for event in soundsInMeasure {
                    if let timeOnlyPasses = event.timeOnlyPasses, timeOnlyPasses.contains(pass) == false {
                        continue
                    }
                    outputSoundDirectives.append(MusicXMLSoundDirective(
                        sourceID: event.sourceID,
                        performedOccurrenceIndex: occurrenceIndex,
                        partID: event.partID,
                        measureNumber: outputMeasureNumber,
                        tick: currentMeasureStartTick + (event.tick - span.startTick),
                        segno: event.segno,
                        coda: event.coda,
                        tocoda: event.tocoda,
                        dalsegno: event.dalsegno,
                        dacapo: event.dacapo,
                        timeOnlyPasses: event.timeOnlyPasses
                    ))
                }
            }

            let pedalsInMeasure = original.pedalEvents.filter { event in
                selectedPartIDs.contains(event.partID) && event.measureNumber == span.measureNumber
            }
            for event in pedalsInMeasure {
                if let timeOnlyPasses = event.timeOnlyPasses, timeOnlyPasses.contains(pass) == false {
                    continue
                }
                outputPedalEvents.append(MusicXMLPedalEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    partID: event.partID,
                    measureNumber: outputMeasureNumber,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    kind: event.kind,
                    controller: event.controller,
                    value: event.value,
                    timeOnlyPasses: event.timeOnlyPasses
                ))
            }

            for event in original.dynamicEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputDynamicEvents.append(MusicXMLDynamicEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    velocity: event.velocity,
                    scope: shiftedScope(event.scope),
                    source: event.source
                ))
            }
            for event in original.wedgeEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputWedgeEvents.append(MusicXMLWedgeEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    kind: event.kind,
                    numberToken: event.numberToken,
                    scope: shiftedScope(event.scope)
                ))
            }
            for event in original.fermataEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputFermataEvents.append(MusicXMLFermataEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    scope: shiftedScope(event.scope),
                    source: event.source
                ))
            }
            for event in original.timeSignatureEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputTimeSignatureEvents.append(MusicXMLTimeSignatureEvent(
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    meter: event.meter,
                    scope: shiftedScope(event.scope)
                ))
            }
            for event in original.keySignatureEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputKeySignatureEvents.append(MusicXMLKeySignatureEvent(
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    fifths: event.fifths,
                    modeToken: event.modeToken,
                    scope: shiftedScope(event.scope)
                ))
            }
            for event in original.clefEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputClefEvents.append(MusicXMLClefEvent(
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    signToken: event.signToken,
                    line: event.line,
                    octaveChange: event.octaveChange,
                    numberToken: event.numberToken,
                    scope: shiftedScope(event.scope)
                ))
            }
            for event in original.transposeEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputTransposeEvents.append(MusicXMLTransposeEvent(
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    diatonic: event.diatonic,
                    chromatic: event.chromatic,
                    octaveChange: event.octaveChange,
                    isDouble: event.isDouble,
                    scope: shiftedScope(event.scope)
                ))
            }
            for event in original.octaveShiftEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputOctaveShiftEvents.append(MusicXMLOctaveShiftEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    kind: event.kind,
                    size: event.size,
                    numberToken: event.numberToken,
                    scope: shiftedScope(event.scope)
                ))
            }
            for event in original.wordsEvents
                where selectedPartIDs.contains(event.scope.partID) && event.tick >= span.startTick && event.tick < span.endTick
            {
                outputWordsEvents.append(MusicXMLWordsEvent(
                    sourceID: event.sourceID,
                    performedOccurrenceIndex: occurrenceIndex,
                    tick: currentMeasureStartTick + (event.tick - span.startTick),
                    text: event.text,
                    scope: shiftedScope(event.scope)
                ))
            }

            for partID in orderedSelectedPartIDs {
                guard let sourceSpan = sourceMeasureSpan(
                    for: partID,
                    matching: span,
                    in: original.measures
                ) else { continue }
                outputMeasures.append(MusicXMLMeasureSpan(
                    partID: partID,
                    measureNumber: outputMeasureNumber,
                    sourceMeasureIndex: sourceSpan.sourceMeasureIndex,
                    sourceMeasureNumberToken: sourceSpan.sourceMeasureNumberToken,
                    occurrenceIndex: occurrenceIndex,
                    startTick: currentMeasureStartTick,
                    endTick: currentMeasureStartTick + duration
                ))
            }

            outputTick += duration
            outputMeasureNumber += 1
        }

        outputNotes.sort { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return (lhs.midiNote ?? -1) < (rhs.midiNote ?? -1)
        }
        outputTempoEvents.sort { $0.tick < $1.tick }
        outputSoundDirectives.sort { $0.tick < $1.tick }
        outputPedalEvents.sort { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            if lhs.controller != rhs.controller { return lhs.controller.rawValue < rhs.controller.rawValue }
            let lhsKey = lhs.value.map { Int($0.midiValue) } ?? 128
            let rhsKey = rhs.value.map { Int($0.midiValue) } ?? 128
            return lhsKey < rhsKey
        }
        outputDynamicEvents.sort { $0.tick < $1.tick }
        outputWedgeEvents.sort { $0.tick < $1.tick }
        outputFermataEvents.sort { $0.tick < $1.tick }
        outputTimeSignatureEvents.sort { $0.tick < $1.tick }
        outputKeySignatureEvents.sort { $0.tick < $1.tick }
        outputClefEvents.sort { $0.tick < $1.tick }
        outputTransposeEvents.sort { $0.tick < $1.tick }
        outputOctaveShiftEvents.sort { $0.tick < $1.tick }
        outputWordsEvents.sort { $0.tick < $1.tick }

        return MusicXMLScore(
            scoreVersion: original.scoreVersion,
            partMetadata: original.partMetadata.filter { selectedPartIDs.contains($0.partID) },
            logicalInstruments: original.logicalInstruments.filter { instrument in
                instrument.memberPartIDs.contains { selectedPartIDs.contains($0) }
            },
            notes: outputNotes,
            tempoEvents: outputTempoEvents,
            soundDirectives: outputSoundDirectives,
            pedalEvents: outputPedalEvents,
            dynamicEvents: outputDynamicEvents,
            wedgeEvents: outputWedgeEvents,
            fermataEvents: outputFermataEvents,
            timeSignatureEvents: outputTimeSignatureEvents,
            keySignatureEvents: outputKeySignatureEvents,
            clefEvents: outputClefEvents,
            transposeEvents: outputTransposeEvents,
            octaveShiftEvents: outputOctaveShiftEvents,
            wordsEvents: outputWordsEvents,
            measures: outputMeasures,
            repeatDirectives: [],
            endingDirectives: []
        )
    }

    private func orderedPartIDs(
        _ selectedPartIDs: Set<String>,
        partMetadata: [MusicXMLPartMetadata]
    ) -> [String] {
        let sourceOrder = partMetadata.map(\.partID) + selectedPartIDs.sorted()
        return sourceOrder.reduce(into: [String]()) { result, partID in
            guard selectedPartIDs.contains(partID), result.contains(partID) == false else { return }
            result.append(partID)
        }
    }

    private func sourceMeasureSpan(
        for partID: String,
        matching primarySpan: MusicXMLMeasureSpan,
        in measures: [MusicXMLMeasureSpan]
    ) -> MusicXMLMeasureSpan? {
        let partMeasures = measures.filter { $0.partID == partID }
        return partMeasures.first { $0.sourceMeasureIndex == primarySpan.sourceMeasureIndex }
            ?? partMeasures.first {
                $0.sourceMeasureNumberToken != nil
                    && $0.sourceMeasureNumberToken == primarySpan.sourceMeasureNumberToken
            }
            ?? partMeasures.first { $0.measureNumber == primarySpan.measureNumber }
    }

    private func shiftedScope(_ scope: MusicXMLEventScope) -> MusicXMLEventScope {
        scope
    }
}

extension MusicXMLStructureExpander {
    private struct JumpInstruction {
        enum Kind {
            case dacapo
            case dalsegno(value: String)
            case tocoda(value: String)
        }

        let tick: Int
        let atMeasureIndex: Int
        let kind: Kind
    }

    func expandSoundJumpsIfPossible(
        score: MusicXMLScore,
        primaryPartID: String = "P1",
        includedPartIDs: Set<String>? = nil
    ) -> MusicXMLStructureExpansionResult {
        let primarySoundDirectives = score.soundDirectives.filter { $0.partID == primaryPartID }
        guard primarySoundDirectives.isEmpty == false else {
            return MusicXMLStructureExpansionResult(score: score, approximationReason: nil)
        }

        let primaryMeasures = score.measures
            .filter { $0.partID == primaryPartID }
            .sorted { $0.startTick < $1.startTick }

        guard primaryMeasures.isEmpty == false else {
            return MusicXMLStructureExpansionResult(score: score, approximationReason: nil)
        }

        var measureIndexByNumber: [Int: Int] = [:]
        for (index, span) in primaryMeasures.enumerated() {
            if measureIndexByNumber[span.measureNumber] == nil {
                measureIndexByNumber[span.measureNumber] = index
            }
        }

        var segnoIndexByValue: [String: Int] = [:]
        var codaIndexByValue: [String: Int] = [:]
        var instructions: [JumpInstruction] = []

        for directive in primarySoundDirectives {
            guard let index = measureIndexByNumber[directive.measureNumber] else { continue }

            if let value = directive.segno {
                if segnoIndexByValue[value] == nil {
                    segnoIndexByValue[value] = index
                }
            }

            if let value = directive.coda {
                if codaIndexByValue[value] == nil {
                    codaIndexByValue[value] = index
                }
            }

            if let value = directive.tocoda {
                instructions.append(JumpInstruction(
                    tick: directive.tick,
                    atMeasureIndex: index,
                    kind: .tocoda(value: value)
                ))
            }

            if let value = directive.dalsegno {
                instructions.append(JumpInstruction(
                    tick: directive.tick,
                    atMeasureIndex: index,
                    kind: .dalsegno(value: value)
                ))
            }

            if directive.dacapo != nil {
                instructions.append(JumpInstruction(tick: directive.tick, atMeasureIndex: index, kind: .dacapo))
            }
        }

        guard instructions.isEmpty == false else {
            return MusicXMLStructureExpansionResult(score: score, approximationReason: nil)
        }

        let instructionsByMeasure = Dictionary(grouping: instructions) { $0.atMeasureIndex }

        var outputSequence: [Int] = []
        outputSequence.reserveCapacity(min(primaryMeasures.count * 2, maxOutputMeasures))

        var currentIndex = 0
        var jumpCount = 0
        var executedInstructionIDs: Set<String> = []
        var limitReason: String?

        while currentIndex < primaryMeasures.count {
            if outputSequence.count >= maxOutputMeasures {
                limitReason = "structure-expansion-output-measure-limit"
                break
            }
            if jumpCount >= maxJumps {
                limitReason = "structure-expansion-jump-limit"
                break
            }

            outputSequence.append(currentIndex)

            guard let candidateInstructions = instructionsByMeasure[currentIndex] else {
                currentIndex += 1
                continue
            }

            let sortedCandidates = candidateInstructions.sorted { $0.tick < $1.tick }
            var didJump = false

            for instruction in sortedCandidates {
                let instructionID = switch instruction.kind {
                case .dacapo:
                    "\(instruction.tick)-\(instruction.atMeasureIndex)-dacapo"
                case let .dalsegno(value):
                    "\(instruction.tick)-\(instruction.atMeasureIndex)-dalsegno-\(value)"
                case let .tocoda(value):
                    "\(instruction.tick)-\(instruction.atMeasureIndex)-tocoda-\(value)"
                }
                guard executedInstructionIDs.contains(instructionID) == false else { continue }

                let destinationIndex: Int? = switch instruction.kind {
                case .dacapo:
                    0
                case let .dalsegno(value):
                    segnoIndexByValue[value]
                case let .tocoda(value):
                    codaIndexByValue[value]
                }

                guard let destinationIndex else { continue }
                executedInstructionIDs.insert(instructionID)
                jumpCount += 1
                currentIndex = destinationIndex
                didJump = true
                break
            }

            if didJump == false {
                currentIndex += 1
            }
        }

        if let limitReason {
            return MusicXMLStructureExpansionResult(score: score, approximationReason: limitReason)
        }

        return MusicXMLStructureExpansionResult(
            score: materializeExpandedScore(
                original: score,
                primaryPartID: primaryPartID,
                primaryMeasures: primaryMeasures,
                sequence: outputSequence.map { MeasureVisit(index: $0, repeatPass: nil) },
                includeSoundDirectives: false,
                includedPartIDs: includedPartIDs
            ),
            approximationReason: nil
        )
    }
}
