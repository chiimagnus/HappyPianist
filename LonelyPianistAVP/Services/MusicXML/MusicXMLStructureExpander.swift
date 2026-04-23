import Foundation

struct MusicXMLStructureExpander {
    func expandStructureIfPossible(score: MusicXMLScore, primaryPartID: String = "P1") -> MusicXMLScore {
        let afterRepeat = expandRepeatAndEndingIfPossible(score: score, primaryPartID: primaryPartID)
        return expandSoundJumpsIfPossible(score: afterRepeat, primaryPartID: primaryPartID)
    }

    func expandRepeatAndEndingIfPossible(score: MusicXMLScore, primaryPartID: String = "P1") -> MusicXMLScore {
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
            includeSoundDirectives: true
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
        includeSoundDirectives: Bool
    ) -> MusicXMLScore {
        var outputNotes: [MusicXMLNoteEvent] = []
        var outputTempoEvents: [MusicXMLTempoEvent] = []
        var outputSoundDirectives: [MusicXMLSoundDirective] = []
        var outputPedalEvents: [MusicXMLPedalEvent] = []
        var outputMeasures: [MusicXMLMeasureSpan] = []

        outputNotes.reserveCapacity(original.notes.count)
        outputTempoEvents.reserveCapacity(original.tempoEvents.count)
        outputSoundDirectives.reserveCapacity(original.soundDirectives.count)
        outputPedalEvents.reserveCapacity(original.pedalEvents.count)
        outputMeasures.reserveCapacity(sequence.count)

        var outputTick = 0
        var outputMeasureNumber = 1

        for index in sequence {
            guard primaryMeasures.indices.contains(index) else { continue }
            let span = primaryMeasures[index]
            let duration = max(0, span.endTick - span.startTick)
            let currentMeasureStartTick = outputTick

            let notesInMeasure = original.notes.filter { note in
                note.partID == primaryPartID && note.tick >= span.startTick && note.tick < span.endTick
            }
            for note in notesInMeasure {
                let shiftedTick = currentMeasureStartTick + (note.tick - span.startTick)
                outputNotes.append(
                    MusicXMLNoteEvent(
                        partID: note.partID,
                        measureNumber: outputMeasureNumber,
                        tick: shiftedTick,
                        durationTicks: note.durationTicks,
                        midiNote: note.midiNote,
                        isRest: note.isRest,
                        isChord: note.isChord,
                        tieStart: note.tieStart,
                        tieStop: note.tieStop,
                        staff: note.staff,
                        voice: note.voice
                    )
                )
            }

            let temposInMeasure = original.tempoEvents.filter { event in
                event.tick >= span.startTick && event.tick < span.endTick
            }
            for event in temposInMeasure {
                let shiftedTick = currentMeasureStartTick + (event.tick - span.startTick)
                outputTempoEvents.append(MusicXMLTempoEvent(tick: shiftedTick, quarterBPM: event.quarterBPM))
            }

            if includeSoundDirectives {
                let soundsInMeasure = original.soundDirectives.filter { event in
                    event.partID == primaryPartID && event.measureNumber == span.measureNumber
                }
                for event in soundsInMeasure {
                    let shiftedTick = currentMeasureStartTick + (event.tick - span.startTick)
                    outputSoundDirectives.append(
                        MusicXMLSoundDirective(
                            partID: primaryPartID,
                            measureNumber: outputMeasureNumber,
                            tick: shiftedTick,
                            segno: event.segno,
                            coda: event.coda,
                            tocoda: event.tocoda,
                            dalsegno: event.dalsegno,
                            dacapo: event.dacapo
                        )
                    )
                }
            }

            let pedalsInMeasure = original.pedalEvents.filter { event in
                event.partID == primaryPartID && event.measureNumber == span.measureNumber
            }
            for event in pedalsInMeasure {
                let shiftedTick = currentMeasureStartTick + (event.tick - span.startTick)
                outputPedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: primaryPartID,
                        measureNumber: outputMeasureNumber,
                        tick: shiftedTick,
                        kind: event.kind,
                        isDown: event.isDown
                    )
                )
            }

            outputMeasures.append(
                MusicXMLMeasureSpan(
                    partID: primaryPartID,
                    measureNumber: outputMeasureNumber,
                    startTick: currentMeasureStartTick,
                    endTick: currentMeasureStartTick + duration
                )
            )

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

        return MusicXMLScore(
            notes: outputNotes,
            tempoEvents: outputTempoEvents,
            soundDirectives: outputSoundDirectives,
            pedalEvents: outputPedalEvents,
            measures: outputMeasures,
            repeatDirectives: [],
            endingDirectives: []
        )
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
        maxJumps: Int = 64
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
            #if DEBUG
                print(
                    "MusicXMLStructureExpander: jump expansion hit limit (measures=\(outputSequence.count), jumps=\(jumpCount)); falling back to linear score"
                )
            #endif
            return score
        }

        return materializeExpandedScore(
            original: score,
            primaryPartID: primaryPartID,
            primaryMeasures: primaryMeasures,
            sequence: outputSequence,
            includeSoundDirectives: false
        )
    }
}
