import Foundation

extension MusicXMLParserDelegate {
    func finalizeNote() {
        guard let duration = state.noteDuration else { return }

        let currentTick = state.partTick[state.currentPartID] ?? state.currentMeasureStartTick
        let startTick: Int
        if state.noteIsChord {
            startTick = state.partLastNonChordStartTick[state.currentPartID] ?? currentTick
        } else {
            startTick = currentTick
            state.partLastNonChordStartTick[state.currentPartID] = startTick
            state.partTick[state.currentPartID] = currentTick + duration
        }

        let midiNote: Int? = if state.noteIsRest {
            nil
        } else {
            Self.makeMIDINote(step: state.noteStep, alter: state.noteAlter ?? 0, octave: state.noteOctave)
        }

        state.notes.append(
            MusicXMLNoteEvent(
                partID: state.currentPartID,
                measureNumber: state.currentMeasureNumber,
                tick: startTick,
                durationTicks: duration,
                midiNote: midiNote,
                isRest: state.noteIsRest,
                isChord: state.noteIsChord,
                tieStart: state.noteTieStart,
                tieStop: state.noteTieStop,
                staff: state.noteStaff,
                voice: state.noteVoice
            )
        )

        let noteEndTick = startTick + duration
        let currentMax = state.partMeasureMaxTick[state.currentPartID] ?? state.currentMeasureStartTick
        state.partMeasureMaxTick[state.currentPartID] = max(
            currentMax,
            noteEndTick,
            state.partTick[state.currentPartID] ?? currentTick
        )
    }

    static func makeMIDINote(step: String?, alter: Int, octave: Int?) -> Int? {
        guard let step, let octave else { return nil }
        let stepBase: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]
        guard let base = stepBase[step] else { return nil }
        return (octave + 1) * 12 + base + alter
    }
}
