import SwiftUI

protocol GrandStaffNotationRendererProtocol {
    func draw(
        presentation: GrandStaffNotationPresentation,
        in context: GraphicsContext,
        displayScale: CGFloat
    )
}
