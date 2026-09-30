import CoreGraphics

struct GrandStaffNotationSystemCanvasLayoutService {
    struct Layout: Equatable {
        let size: CGSize
        let context: GrandStaffNotationContext?
        let header: GrandStaffNotationSignatureLayout
        let lineSpacing: CGFloat
        let contentMinX: CGFloat
        let contentMaxX: CGFloat
        let trebleBottomLineY: CGFloat
        var bassBottomLineY: CGFloat { trebleBottomLineY + 8 * lineSpacing }
        var trebleTopLineY: CGFloat { trebleBottomLineY - 4 * lineSpacing }
        var bassTopLineY: CGFloat { bassBottomLineY - 4 * lineSpacing }
        var noteWidth: CGFloat { lineSpacing * 1.688 }
        var noteHeight: CGFloat { lineSpacing }
        var noteheadColumnWidth: CGFloat { lineSpacing * 1.18 }
        var smuflFontSize: CGFloat { lineSpacing * 4 }
        func xPosition(_ normalized: Double) -> CGFloat { contentMinX + normalized * (contentMaxX - contentMinX) }
        func yPosition(staffStep: Int, staffNumber: Int) -> CGFloat {
            (staffNumber == 2 ? bassBottomLineY : trebleBottomLineY) - Double(staffStep) * lineSpacing / 2
        }
    }

    func makeLayout(system: GrandStaffNotationPagePlan.System, staffSpace: Double) -> Layout {
        let spacing = staffSpace * system.scale
        let contentMinX = system.musicOriginX * spacing
        return .init(size: CGSize(width: system.rect.width * spacing, height: system.rect.height * spacing), context: system.notation.context, header: system.header, lineSpacing: spacing, contentMinX: contentMinX, contentMaxX: contentMinX + system.musicWidth * spacing, trebleBottomLineY: -system.rect.minY * spacing)
    }
}
