import UIKit

enum AVPOverlayPalette {
    // Calibration
    static let reticleColor: UIColor = .systemYellow.withAlphaComponent(0.9)
    static let reticleReadyColor: UIColor = .systemGreen.withAlphaComponent(0.9)
    static let a0AnchorColor: UIColor = .systemBlue.withAlphaComponent(0.9)
    static let c8AnchorColor: UIColor = .systemPurple.withAlphaComponent(0.9)

    // Practice feedback
    static let guideColor: UIColor = .init(red: 1.00, green: 0.93, blue: 0.78, alpha: 1.0)
    static let rightHandGuideColor: UIColor = guideColor
    static let leftHandGuideColor: UIColor = .systemCyan.withAlphaComponent(0.95)
}
