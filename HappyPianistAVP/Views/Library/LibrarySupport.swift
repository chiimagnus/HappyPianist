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

struct SongLibraryTrackPresentation {
  let title: String
  let subtitle: String
  let labelColor: Color
  let knownDuration: TimeInterval?

  init(entry: SongLibraryEntry, index: Int) {
    title = entry.displayName.replacing("_", with: " ")

    let normalizedTitle = entry.displayName.lowercased()
    switch normalizedTitle {
    case let value where value.localizedStandardContains("bohemian rhapsody"):
      subtitle = "Queen · arr. Phillip Keveren"
      knownDuration = 5 * 60 + 54
    case let value where value.localizedStandardContains("despacito"):
      subtitle = "Peter Bence"
      knownDuration = 4 * 60 + 12
    case let value where value.localizedStandardContains("awesome piano"):
      subtitle = "Peter Bence"
      knownDuration = 3 * 60 + 48
    case let value where value.localizedStandardContains("under pressure"):
      subtitle = "David Bowie & Queen"
      knownDuration = 4 * 60 + 6
    default:
      if entry.isBundled == true {
        subtitle = "内置曲目"
      } else {
        subtitle = "导入于 \(entry.importedAt.formatted(date: .abbreviated, time: .omitted))"
      }
      knownDuration = nil
    }

    let palette: [Color] = [
      Color(red: 77 / 255, green: 127 / 255, blue: 116 / 255),
      Color(red: 197 / 255, green: 106 / 255, blue: 86 / 255),
      Color(red: 189 / 255, green: 148 / 255, blue: 82 / 255),
      Color(red: 138 / 255, green: 100 / 255, blue: 134 / 255),
      Color(red: 74 / 255, green: 102 / 255, blue: 140 / 255),
      Color(red: 142 / 255, green: 112 / 255, blue: 82 / 255),
    ]
    labelColor = palette[index % palette.count]
  }
}
