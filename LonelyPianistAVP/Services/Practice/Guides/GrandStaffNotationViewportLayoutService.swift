import CoreGraphics

struct GrandStaffNotationViewportLayoutService {
    struct StaffStepBounds: Equatable {
        let minTrebleStep: Int
        let maxTrebleStep: Int
        let minBassStep: Int
        let maxBassStep: Int

        static let `default` = StaffStepBounds(
            minTrebleStep: 0,
            maxTrebleStep: 8,
            minBassStep: 0,
            maxBassStep: 8
        )
    }

    struct Layout: Equatable {
        let size: CGSize
        let context: GrandStaffNotationContext?
        let requiredHeight: CGFloat
        let canvasYOffset: CGFloat

        let lineSpacing: CGFloat
        let noteWidth: CGFloat
        let noteHeight: CGFloat

        let contextMinX: CGFloat
        let contextWidth: CGFloat
        let contentMinX: CGFloat
        let contentMaxX: CGFloat

        let trebleTopLineY: CGFloat
        let trebleBottomLineY: CGFloat
        let bassTopLineY: CGFloat
        let bassBottomLineY: CGFloat

        let trebleClefY: CGFloat
        let bassClefY: CGFloat
        let trebleClefFontSize: CGFloat
        let bassClefFontSize: CGFloat
        let keySignatureFontSize: CGFloat
        let timeSignatureFontSize: CGFloat

        func xPosition(_ normalized: Double) -> CGFloat {
            let clamped = max(-0.2, min(1.2, normalized))
            return contentMinX + CGFloat(clamped) * (contentMaxX - contentMinX)
        }

        func yPosition(staffStep: Int, staffNumber: Int) -> CGFloat {
            let bottomLineY = (staffNumber >= 2) ? bassBottomLineY : trebleBottomLineY
            return bottomLineY - CGFloat(staffStep) * lineSpacing / 2
        }
    }

    func makeLayout(
        size: CGSize,
        lineSpacing: CGFloat = 14,
        items: [GrandStaffNotationItem],
        chords: [GrandStaffNotationChord] = [],
        beams: [GrandStaffNotationBeam] = [],
        context: GrandStaffNotationContext?,
        staffStepBounds: StaffStepBounds? = nil
    ) -> Layout {
        let resolvedLineSpacing = max(8, min(22, lineSpacing))

        let bounds = staffStepBounds ?? {
            let trebleSteps = items.filter { $0.staffNumber <= 1 }.map(\.staffStep)
            let bassSteps = items.filter { $0.staffNumber >= 2 }.map(\.staffStep)
            return StaffStepBounds(
                minTrebleStep: trebleSteps.min() ?? 0,
                maxTrebleStep: trebleSteps.max() ?? 8,
                minBassStep: bassSteps.min() ?? 0,
                maxBassStep: bassSteps.max() ?? 8
            )
        }()

        let trebleExtraAboveUnits = CGFloat(max(0, bounds.maxTrebleStep - 8)) * 0.5
        let bassExtraBelowUnits = CGFloat(max(0, -bounds.minBassStep)) * 0.5

        let trebleExtraBelowUnits = CGFloat(max(0, -bounds.minTrebleStep)) * 0.5
        let bassExtraAboveUnits = CGFloat(max(0, bounds.maxBassStep - 8)) * 0.5

        let topPaddingUnits: CGFloat = 2.6
        let bottomPaddingUnits: CGFloat = 1.8
        let staffHeightUnits: CGFloat = 4.0
        // In engraved piano music, the gap between treble/bass staves is typically
        // noticeably larger than the intra-staff line spacing, leaving room for
        // middle-C ledger lines and shared dynamics.
        let baseInterStaffGapUnits: CGFloat = 4.0
        let maxInterStaffGapUnits: CGFloat = 6.0
        let interStaffCollisionPadUnits: CGFloat = 1.4

        let requiredInterStaffGapUnits = trebleExtraBelowUnits + bassExtraAboveUnits + interStaffCollisionPadUnits
        let interStaffGapUnits = min(maxInterStaffGapUnits, max(baseInterStaffGapUnits, requiredInterStaffGapUnits))

        let totalHeightUnits =
            topPaddingUnits
                + trebleExtraAboveUnits
                + staffHeightUnits
                + interStaffGapUnits
                + staffHeightUnits
                + bassExtraBelowUnits
                + bottomPaddingUnits

        let noteWidth = resolvedLineSpacing * 1.05
        let noteHeight = resolvedLineSpacing * 0.70

        let contextMinX: CGFloat = 4
        let contextWidth: CGFloat = resolvedLineSpacing * 7.0
        let contentMinX: CGFloat = contextMinX + contextWidth
        let contentMaxX: CGFloat = min(size.width - 18, size.width * 0.96)

        let topPadding = topPaddingUnits * resolvedLineSpacing
        let trebleTopLineY = topPadding + trebleExtraAboveUnits * resolvedLineSpacing
        let trebleBottomLineY = trebleTopLineY + resolvedLineSpacing * 4
        let bassTopLineY = trebleBottomLineY + interStaffGapUnits * resolvedLineSpacing
        let bassBottomLineY = bassTopLineY + resolvedLineSpacing * 4

        let canvasMetrics = canvasMetrics(
            lineSpacing: resolvedLineSpacing,
            noteWidth: noteWidth,
            noteHeight: noteHeight,
            size: size,
            items: items,
            chords: chords,
            beams: beams,
            trebleBottomLineY: trebleBottomLineY,
            bassBottomLineY: bassBottomLineY,
            contextMinY: 0,
            contextMaxY: totalHeightUnits * resolvedLineSpacing,
            staffStepBounds: bounds
        )

        let trebleClefStep = clefAnchorStaffStep(
            signToken: context?.trebleClefSignToken,
            line: context?.trebleClefLine
        )
        let bassClefStep = clefAnchorStaffStep(
            signToken: context?.bassClefSignToken,
            line: context?.bassClefLine
        )

        let trebleClefY = (trebleClefStep != nil)
            ? (trebleBottomLineY - CGFloat(trebleClefStep ?? 4) * resolvedLineSpacing / 2)
            : (trebleBottomLineY - 4 * resolvedLineSpacing / 2)

        let bassClefY = (bassClefStep != nil)
            ? (bassBottomLineY - CGFloat(bassClefStep ?? 4) * resolvedLineSpacing / 2)
            : (bassBottomLineY - 4 * resolvedLineSpacing / 2)

        // Clef glyphs are drawn via Unicode music symbols and can appear optically smaller than staff height
        // when rendered by the system fallback font. Scale them based on staff spacing rather than keeping
        // them close to the notehead size.
        let trebleClefFontSize = resolvedLineSpacing * 3.8
        let bassClefFontSize = resolvedLineSpacing * 3.3
        let keySignatureFontSize = resolvedLineSpacing * 1.25
        let timeSignatureFontSize = resolvedLineSpacing * 1.35

        return Layout(
            size: CGSize(width: size.width, height: canvasMetrics.requiredHeight),
            context: context,
            requiredHeight: canvasMetrics.requiredHeight,
            canvasYOffset: canvasMetrics.contentYOffset,
            lineSpacing: resolvedLineSpacing,
            noteWidth: noteWidth,
            noteHeight: noteHeight,
            contextMinX: contextMinX,
            contextWidth: contextWidth,
            contentMinX: contentMinX,
            contentMaxX: contentMaxX,
            trebleTopLineY: trebleTopLineY,
            trebleBottomLineY: trebleBottomLineY,
            bassTopLineY: bassTopLineY,
            bassBottomLineY: bassBottomLineY,
            trebleClefY: trebleClefY,
            bassClefY: bassClefY,
            trebleClefFontSize: trebleClefFontSize,
            bassClefFontSize: bassClefFontSize,
            keySignatureFontSize: keySignatureFontSize,
            timeSignatureFontSize: timeSignatureFontSize
        )
    }

    private struct CanvasMetrics: Equatable {
        let requiredHeight: CGFloat
        let contentYOffset: CGFloat
    }

    private func canvasMetrics(
        lineSpacing: CGFloat,
        noteWidth: CGFloat,
        noteHeight: CGFloat,
        size: CGSize,
        items: [GrandStaffNotationItem],
        chords: [GrandStaffNotationChord],
        beams: [GrandStaffNotationBeam],
        trebleBottomLineY: CGFloat,
        bassBottomLineY: CGFloat,
        contextMinY: CGFloat,
        contextMaxY: CGFloat,
        staffStepBounds: StaffStepBounds
    ) -> CanvasMetrics {
        var minY: CGFloat = contextMinY
        var maxY: CGFloat = contextMaxY

        func yPosition(staffStep: Int, staffNumber: Int) -> CGFloat {
            let bottomLineY = (staffNumber >= 2) ? bassBottomLineY : trebleBottomLineY
            return bottomLineY - CGFloat(staffStep) * lineSpacing / 2
        }

        // Keep the scrollable vertical extents stable so the staff doesn't "jump"
        // when a high/low note enters or leaves the horizontal window.
        let trebleTopY = yPosition(staffStep: staffStepBounds.maxTrebleStep, staffNumber: 1)
        let trebleBottomY = yPosition(staffStep: staffStepBounds.minTrebleStep, staffNumber: 1)
        let bassTopY = yPosition(staffStep: staffStepBounds.maxBassStep, staffNumber: 2)
        let bassBottomY = yPosition(staffStep: staffStepBounds.minBassStep, staffNumber: 2)

        minY = min(minY, trebleTopY - noteHeight * 0.9)
        minY = min(minY, bassTopY - noteHeight * 0.9)
        maxY = max(maxY, trebleBottomY + noteHeight * 0.9)
        maxY = max(maxY, bassBottomY + noteHeight * 0.9)

        // Add deterministic headroom/footroom so stems and beams won't clip,
        // while keeping the scroll extents stable (no vertical jumping).
        let beamStrokeWidth = max(2, lineSpacing * 0.42)
        let maxBeamCount = 3
        let stemLength = lineSpacing * 3.2
        let beamGap = max(1.2, lineSpacing * 0.28)
        let beamStackStride = beamStrokeWidth + beamGap
        let headroom = stemLength + CGFloat(max(0, maxBeamCount - 1)) * beamStackStride + beamStrokeWidth

        minY -= headroom
        maxY += headroom * 0.65

        let padding: CGFloat = lineSpacing * 0.8
        let requiredHeight = max(1, (maxY - minY) + padding * 2)
        let contentYOffset = -minY + padding
        return CanvasMetrics(requiredHeight: requiredHeight, contentYOffset: contentYOffset)
    }

    private func beamCountFor(noteValue: GrandStaffNoteValue) -> Int {
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

    private func clefAnchorStaffStep(signToken: String?, line: Int?) -> Int? {
        if let line, (1 ... 5).contains(line) {
            return (line - 1) * 2
        }

        guard let token = signToken?.uppercased(), token.isEmpty == false else { return nil }
        switch token {
            case "G":
                return 2
            case "F":
                return 6
            case "C":
                return 4
            default:
                return nil
        }
    }
}
