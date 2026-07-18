import Foundation

struct MusicXMLStructureExpander {
    func expandStructureIfPossible(
        score: MusicXMLScore,
        primaryPartID: String = "P1",
        includedPartIDs: Set<String>? = nil
    ) -> MusicXMLScore {
        let afterRepeat = expandRepeatAndEndingIfPossible(
            score: score,
            primaryPartID: primaryPartID,
            includedPartIDs: includedPartIDs
        )
        return expandSoundJumpsIfPossible(
            score: afterRepeat,
            primaryPartID: primaryPartID,
            includedPartIDs: includedPartIDs
        )
    }

    func expandRepeatAndEndingIfPossible(
        score: MusicXMLScore,
        primaryPartID: String = "P1",
        includedPartIDs: Set<String>? = nil
    ) -> MusicXMLScore {
        let primaryMeasures = score.measures
            .filter { $0.partID == primaryPartID }
            .sorted { $0.startTick < $1.startTick }

        guard primaryMeasures.isEmpty == false else { return score }

        var measureIndexByNumber: [Int: Int] = [:]
        for (index, span) in primaryMeasures.enumerated() {
            if measureIndexByNumber[span.measureNumber] == nil {
                measureIndexByNumber[span.measureNumber] = index
            }
        }

        let repeats = score.repeatDirectives.filter { $0.partID == primaryPartID }
        guard let forward = repeats.first(where: { $0.direction == .forward }),
              let forwardIndex = measureIndexByNumber[forward.measureNumber]
        else {
            return score
        }

        let backwardCandidate = repeats.first(where: { directive in
            directive.direction == .backward && (measureIndexByNumber[directive.measureNumber] ?? -1) >= forwardIndex
        })

        guard let backward = backwardCandidate,
              let backwardIndex = measureIndexByNumber[backward.measureNumber],
              backwardIndex > forwardIndex
        else {
            return score
        }

        let endingSpans = resolveEndingSpans(
            directives: score.endingDirectives.filter { $0.partID == primaryPartID },
            measureIndexByNumber: measureIndexByNumber
        )

        let ending1 = endingSpans["1"]
        let ending2 = endingSpans["2"]

        var sequence: [Int] = []
        sequence.append(contentsOf: 0 ..< forwardIndex)
        sequence.append(contentsOf: forwardIndex ... backwardIndex)

        if let ending1,
           ending1.endIndex == backwardIndex,
           let ending2,
           ending2.startIndex == backwardIndex + 1
        {
            if ending1.startIndex > forwardIndex {
                sequence.append(contentsOf: forwardIndex ..< ending1.startIndex)
            }
            sequence.append(contentsOf: ending2.startIndex ... ending2.endIndex)

            let resumeIndex = ending2.endIndex + 1
            if resumeIndex < primaryMeasures.count {
                sequence.append(contentsOf: resumeIndex ..< primaryMeasures.count)
            }
        } else {
            sequence.append(contentsOf: forwardIndex ... backwardIndex)
            let resumeIndex = backwardIndex + 1
            if resumeIndex < primaryMeasures.count {
                sequence.append(contentsOf: resumeIndex ..< primaryMeasures.count)
            }
        }

        return materializeExpandedScore(
            original: score,
            primaryPartID: primaryPartID,
            primaryMeasures: primaryMeasures,
            sequence: sequence,
            includeSoundDirectives: true,
            includedPartIDs: includedPartIDs
        )
    }

    private struct EndingSpan {
        let startIndex: Int
        let endIndex: Int
    }

    private func resolveEndingSpans(
        directives: [MusicXMLEndingDirective],
        measureIndexByNumber: [Int: Int]
    ) -> [String: EndingSpan] {
        let indexedDirectives = directives.compactMap { directive -> (Int, MusicXMLEndingDirective)? in
            guard let index = measureIndexByNumber[directive.measureNumber] else { return nil }
            return (index, directive)
        }
        .sorted { $0.0 < $1.0 }

        var activeStartByNumber: [String: Int] = [:]
        var spans: [String: EndingSpan] = [:]

        for (measureIndex, directive) in indexedDirectives {
            let numbers = directive.number
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }

            if directive.type == .start {
                for number in numbers {
                    if activeStartByNumber[number] == nil {
                        activeStartByNumber[number] = measureIndex
                    }
                }
                continue
            }

            if directive.type == .stop || directive.type == .discontinue {
                for number in numbers {
                    guard spans[number] == nil, let start = activeStartByNumber[number] else { continue }
                    spans[number] = EndingSpan(startIndex: start, endIndex: measureIndex)
                }
            }
        }

        return spans
    }

    private func materializeExpandedScore(
        original: MusicXMLScore,
        primaryPartID: String,
        primaryMeasures: [MusicXMLMeasureSpan],
        sequence: [Int],
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

        for (occurrenceIndex, index) in sequence.enumerated() {
            guard primaryMeasures.indices.contains(index) else { continue }
            let span = primaryMeasures[index]
            let duration = max(0, span.endTick - span.startTick)
            let currentMeasureStartTick = outputTick
            let sourceMeasureID = span.sourceMeasureID
            let pass = (passBySourceMeasureID[sourceMeasureID] ?? 0) + 1
            passBySourceMeasureID[sourceMeasureID] = pass

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
                        fingeringText: note.fingeringText,
                        dotCount: note.dotCount
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
                    isDown: event.isDown,
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
            let lhsKey = lhs.isDown.map { $0 ? 1 : 0 } ?? 2
            let rhsKey = rhs.isDown.map { $0 ? 1 : 0 } ?? 2
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
        maxOutputMeasures: Int = 10000,
        maxJumps: Int = 64,
        includedPartIDs: Set<String>? = nil
    ) -> MusicXMLScore {
        let primarySoundDirectives = score.soundDirectives.filter { $0.partID == primaryPartID }
        guard primarySoundDirectives.isEmpty == false else { return score }

        let primaryMeasures = score.measures
            .filter { $0.partID == primaryPartID }
            .sorted { $0.startTick < $1.startTick }

        guard primaryMeasures.isEmpty == false else { return score }

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

        guard instructions.isEmpty == false else { return score }

        let instructionsByMeasure = Dictionary(grouping: instructions) { $0.atMeasureIndex }

        var outputSequence: [Int] = []
        outputSequence.reserveCapacity(min(primaryMeasures.count * 2, maxOutputMeasures))

        var currentIndex = 0
        var jumpCount = 0
        var executedInstructionIDs: Set<String> = []
        var didHitLimit = false

        while currentIndex < primaryMeasures.count {
            if outputSequence.count >= maxOutputMeasures || jumpCount >= maxJumps {
                didHitLimit = true
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

        if didHitLimit {
            return score
        }

        return materializeExpandedScore(
            original: score,
            primaryPartID: primaryPartID,
            primaryMeasures: primaryMeasures,
            sequence: outputSequence,
            includeSoundDirectives: false,
            includedPartIDs: includedPartIDs
        )
    }
}
