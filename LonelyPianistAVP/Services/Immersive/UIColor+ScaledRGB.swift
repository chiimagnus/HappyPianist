import UIKit

extension UIColor {
    func scaledRGB(intensity: Double) -> UIColor {
        let clamped = CGFloat(max(0, min(1, intensity)))

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return self
        }

        return UIColor(
            red: max(0, min(1, r * clamped)),
            green: max(0, min(1, g * clamped)),
            blue: max(0, min(1, b * clamped)),
            alpha: 1
        )
    }
}

