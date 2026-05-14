import CoreGraphics

struct GrandStaffNotationViewportLayoutService {
    struct Layout: Equatable {
        let size: CGSize
        let context: GrandStaffNotationContext?

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
        items: [GrandStaffNotationItem],
        context: GrandStaffNotationContext?
    ) -> Layout {
        let trebleSteps = items.filter { $0.staffNumber <= 1 }.map(\.staffStep)
        let bassSteps = items.filter { $0.staffNumber >= 2 }.map(\.staffStep)

        let minTrebleStep = trebleSteps.min() ?? 0
        let maxTrebleStep = trebleSteps.max() ?? 8
        let minBassStep = bassSteps.min() ?? 0
        let maxBassStep = bassSteps.max() ?? 8

        let trebleExtraAboveUnits = CGFloat(max(0, maxTrebleStep - 8)) * 0.5
        let bassExtraBelowUnits = CGFloat(max(0, -minBassStep)) * 0.5

        let trebleExtraBelowUnits = CGFloat(max(0, -minTrebleStep)) * 0.5
        let bassExtraAboveUnits = CGFloat(max(0, maxBassStep - 8)) * 0.5

        let topPaddingUnits: CGFloat = 2.2
        let bottomPaddingUnits: CGFloat = 1.8
        let staffHeightUnits: CGFloat = 4.0
        let baseInterStaffGapUnits: CGFloat = 2.8
        let interStaffCollisionPadUnits: CGFloat = 1.4

        let requiredInterStaffGapUnits = trebleExtraBelowUnits + bassExtraAboveUnits + interStaffCollisionPadUnits
        let interStaffGapUnits = max(baseInterStaffGapUnits, requiredInterStaffGapUnits)

        let totalHeightUnits =
            topPaddingUnits
            + trebleExtraAboveUnits
            + staffHeightUnits
            + interStaffGapUnits
            + staffHeightUnits
            + bassExtraBelowUnits
            + bottomPaddingUnits

        let minLineSpacing: CGFloat = 4
        let maxLineSpacing: CGFloat = 18
        let resolvedLineSpacing = max(minLineSpacing, min(maxLineSpacing, size.height / max(1, totalHeightUnits)))

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

        let trebleClefFontSize = resolvedLineSpacing * 2.65
        let bassClefFontSize = resolvedLineSpacing * 2.35
        let keySignatureFontSize = resolvedLineSpacing * 1.25
        let timeSignatureFontSize = resolvedLineSpacing * 1.35

        return Layout(
            size: size,
            context: context,
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

    private func clefAnchorStaffStep(signToken: String?, line: Int?) -> Int? {
        if let line, (1...5).contains(line) {
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
