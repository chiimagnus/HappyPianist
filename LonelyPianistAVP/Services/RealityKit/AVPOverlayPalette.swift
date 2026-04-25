import UIKit

enum AVPOverlayPalette {
    // Calibration
    static let reticleColor: UIColor = .systemYellow.withAlphaComponent(0.9)
    static let reticleReadyColor: UIColor = .systemGreen.withAlphaComponent(0.9)
    static let a0AnchorColor: UIColor = .systemBlue.withAlphaComponent(0.9)
    static let c8AnchorColor: UIColor = .systemPurple.withAlphaComponent(0.9)

    /// Hand tracking debug
    static let handTipColor: UIColor = .systemGreen.withAlphaComponent(0.9)

    // Practice feedback
    static let feedbackNoneColor: UIColor = .init(red: 1.00, green: 0.93, blue: 0.78, alpha: 1.0)
    static let feedbackCorrectColor: UIColor = .init(red: 1.00, green: 0.95, blue: 0.82, alpha: 1.0)
    static let feedbackWrongColor: UIColor = .init(red: 1.00, green: 0.88, blue: 0.78, alpha: 1.0)
}
