import simd

enum BeamColorToken: Equatable {
    case guide
    case correct
    case wrong
}

struct PianoGuideBeamDescriptor: Equatable, Identifiable {
    var id: String {
        "\(midiNote)-\(guideID)"
    }

    let midiNote: Int
    let guideID: Int
    let positionLocal: SIMD3<Float>
    let sizeLocal: SIMD3<Float>
    let surfaceLocalY: Float
    let baseColor: BeamColorToken
    let alpha: Float
}

extension PianoGuideBeamDescriptor {
    private static let beamHeightMeters: Float = 0.18
    private static let beamAlpha: Float = 0.32
    private static let minimumBeamWidthMeters: Float = 0.010
    private static let minimumBeamDepthMeters: Float = 0.018

    static func makeDescriptors(
        highlightGuide: PianoHighlightGuide?,
        keyboardGeometry: PianoKeyboardGeometry?,
        feedbackState: PracticeSessionViewModel.VisualFeedbackState
    ) -> [PianoGuideBeamDescriptor] {
        guard let highlightGuide, let keyboardGeometry else { return [] }

        let desiredNotes = highlightGuide.highlightedMIDINotes.sorted()
        guard desiredNotes.isEmpty == false else { return [] }

        let baseColor: BeamColorToken = switch feedbackState {
            case .none:
                .guide
            case .correct:
                .correct
            case .wrong:
                .wrong
        }

        return desiredNotes.compactMap { midiNote in
            guard let key = keyboardGeometry.key(for: midiNote) else { return nil }

            let width = max(minimumBeamWidthMeters, key.beamFootprintSizeLocal.x)
            let depth = max(minimumBeamDepthMeters, key.beamFootprintSizeLocal.y)
            let height = beamHeightMeters

            let positionLocal = SIMD3<Float>(
                key.beamFootprintCenterLocal.x,
                key.surfaceLocalY + height / 2,
                key.beamFootprintCenterLocal.z
            )

            return PianoGuideBeamDescriptor(
                midiNote: midiNote,
                guideID: highlightGuide.id,
                positionLocal: positionLocal,
                sizeLocal: SIMD3<Float>(width, height, depth),
                surfaceLocalY: key.surfaceLocalY,
                baseColor: baseColor,
                alpha: beamAlpha
            )
        }
    }
}
