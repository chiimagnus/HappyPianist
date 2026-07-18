import simd

struct PianoGuideBeamDescriptor: Equatable, Identifiable {
    var id: String {
        "\(midiNote)-\(guideID)-\(staffNumber ?? 0)"
    }

    let midiNote: Int
    let guideID: Int
    let staffNumber: Int?
    let phase: PianoGuideHighlightPhase
    let keyKind: PianoKeyKind
    let positionLocal: SIMD3<Float>
    let sizeLocal: SIMD3<Float>
    let surfaceLocalY: Float
}

extension PianoGuideBeamDescriptor {
    private static let decalEpsilonMeters: Float = 0.0015
    private static let decalThicknessMeters: Float = 0.001
    private static let decalInsetScale: Float = 0.98

    static func makeDescriptors(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?
    ) -> [PianoGuideBeamDescriptor] {
        guard let highlightGuide, let keyboardGeometry else { return [] }

        let desiredNotes = highlightGuide.highlightedMIDINotes.sorted()
        guard desiredNotes.isEmpty == false else { return [] }

        let highlightsByMidi = PianoGuideKeyHighlightResolver().resolveHighlights(guide: highlightGuide)

        return desiredNotes.compactMap { midiNote in
            guard let key = keyboardGeometry.key(for: midiNote) else { return nil }
            guard let highlight = highlightsByMidi[midiNote] else { return nil }

            let positionLocal = SIMD3<Float>(
                key.localCenter.x,
                key.surfaceLocalY + decalEpsilonMeters,
                key.localCenter.z
            )

            return PianoGuideBeamDescriptor(
                midiNote: midiNote,
                guideID: highlightGuide.id,
                staffNumber: highlight.staffNumber,
                phase: highlight.phase,
                keyKind: key.kind,
                positionLocal: positionLocal,
                sizeLocal: SIMD3<Float>(
                    key.localSize.x * decalInsetScale,
                    decalThicknessMeters,
                    key.localSize.z * decalInsetScale
                ),
                surfaceLocalY: key.surfaceLocalY
            )
        }
    }
}
