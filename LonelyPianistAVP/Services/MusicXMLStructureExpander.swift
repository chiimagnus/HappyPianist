import Foundation

struct MusicXMLStructureExpander {
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
            sequence: sequence
        )
    }

    private struct EndingSpan: Sendable {
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
        sequence: [Int]
    ) -> MusicXMLScore {
        var outputNotes: [MusicXMLNoteEvent] = []
        var outputTempoEvents: [MusicXMLTempoEvent] = []
        var outputMeasures: [MusicXMLMeasureSpan] = []

        outputNotes.reserveCapacity(original.notes.count)
        outputTempoEvents.reserveCapacity(original.tempoEvents.count)
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

        return MusicXMLScore(
            notes: outputNotes,
            tempoEvents: outputTempoEvents,
            measures: outputMeasures,
            repeatDirectives: [],
            endingDirectives: []
        )
    }
}

