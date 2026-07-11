import SwiftUI

enum LibraryDesignTokens {
    static let text = Color.primary
    static let secondaryText = Color.secondary
    static let faintText = Color.primary.opacity(0.45)
    static let line = Color.primary.opacity(0.16)
    static let accent = Color(red: 233 / 255, green: 195 / 255, blue: 122 / 255)
    static let accentForeground = Color(red: 58 / 255, green: 44 / 255, blue: 18 / 255)

    static let recordReferenceDiameter: CGFloat = 236
    static let recordDiameter: CGFloat = 304
    static let recordScale = recordDiameter / recordReferenceDiameter
    static let recordSpacing: CGFloat = 294
    static let sideRecordScale: CGFloat = 0.80
    static let crateMinimumHeight: CGFloat = 410

    static let windowMinimumHeight: CGFloat = 620
    static let windowIdealHeight: CGFloat = 720
    static let windowMaximumHeight: CGFloat = 860

    static let liftMaximum: CGFloat = 72
    static let liftTrigger: CGFloat = 44

    static let tonearmLength: CGFloat = 184
    static let tonearmPivotX: CGFloat = 264
    static let tonearmPivotY: CGFloat = -2.5
    static let armrestCenterX: CGFloat = 237.5
    static let armrestCenterY: CGFloat = 176

    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.62)
    static let easeOut = Animation.timingCurve(0.16, 1, 0.30, 1, duration: 0.56)
}
