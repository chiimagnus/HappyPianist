import simd

struct PianoGuideBeamDescriptor: Equatable, Identifiable {
    var id: String {
        "\(midiNote)-\(guideID)-\(hand.rawValue)"
    }

    let midiNote: Int
    let guideID: Int
    let hand: ScoreHand
    let positionLocal: SIMD3<Float>
    let sizeLocal: SIMD3<Float>
    let surfaceLocalY: Float
    let alpha: Float
}

extension PianoGuideBeamDescriptor {
    private static let decalEpsilonMeters: Float = 0.0015
    private static let decalThicknessMeters: Float = 0.001
    private static let decalInsetScale: Float = 0.98
    private static let decalAlpha: Float = 0.32

    static func makeDescriptors(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?
    ) -> [PianoGuideBeamDescriptor] {
        guard let highlightGuide, let keyboardGeometry else { return [] }

        let desiredNotes = highlightGuide.highlightedMIDINotes.sorted()
        guard desiredNotes.isEmpty == false else { return [] }

        func resolvedHand(notes: [PianoHighlightNote]) -> ScoreHand? {
            guard notes.isEmpty == false else { return nil }
            if notes.contains(where: { $0.hand == .left }) { return .left }
            return .right
        }

        var triggeredNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in highlightGuide.triggeredNotes {
            triggeredNotesByMidi[note.midiNote, default: []].append(note)
        }

        var activeNotesByMidi: [Int: [PianoHighlightNote]] = [:]
        for note in highlightGuide.activeNotes {
            activeNotesByMidi[note.midiNote, default: []].append(note)
        }

        return desiredNotes.compactMap { midiNote in
            guard let key = keyboardGeometry.key(for: midiNote) else { return nil }

            let hand = triggeredNotesByMidi[midiNote].flatMap(resolvedHand)
                ?? activeNotesByMidi[midiNote].flatMap(resolvedHand)
                ?? .right

            let positionLocal = SIMD3<Float>(
                key.localCenter.x,
                key.surfaceLocalY + decalEpsilonMeters,
                key.localCenter.z
            )

            return PianoGuideBeamDescriptor(
                midiNote: midiNote,
                guideID: highlightGuide.id,
                hand: hand,
                positionLocal: positionLocal,
                sizeLocal: SIMD3<Float>(
                    key.localSize.x * decalInsetScale,
                    decalThicknessMeters,
                    key.localSize.z * decalInsetScale
                ),
                surfaceLocalY: key.surfaceLocalY,
                alpha: decalAlpha
            )
        }
    }
}
