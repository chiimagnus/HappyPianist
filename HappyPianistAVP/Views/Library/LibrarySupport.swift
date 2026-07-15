import SwiftUI

enum LibraryDesignTokens {
  static let text = Color.primary
  static let secondaryText = Color.secondary
  static let faintText = Color.primary.opacity(0.45)
  static let line = Color.primary.opacity(0.16)
  static let accent = Color(red: 233 / 255, green: 195 / 255, blue: 122 / 255)
  static let accentForeground = Color(red: 58 / 255, green: 44 / 255, blue: 18 / 255)

  static let practiceInk = Color.primary
  static let practiceSecondaryInk = Color.secondary
  static let practiceLine = Color.primary.opacity(0.14)
  static let practiceAccent = Color(red: 240 / 255, green: 139 / 255, blue: 82 / 255)
  static let practiceAccentDeep = Color(red: 151 / 255, green: 70 / 255, blue: 34 / 255)
  static let practiceStable = Color(red: 111 / 255, green: 155 / 255, blue: 117 / 255)
  static let practiceLearning = Color(red: 217 / 255, green: 162 / 255, blue: 92 / 255)
  static let practiceUnpracticed = Color(red: 216 / 255, green: 208 / 255, blue: 201 / 255)
  static let practiceUnpracticedInk = Color(red: 133 / 255, green: 122 / 255, blue: 115 / 255)
  static let practiceKeyboardTop = Color(red: 58 / 255, green: 44 / 255, blue: 40 / 255)
  static let practiceKeyboardDark = Color(red: 41 / 255, green: 30 / 255, blue: 27 / 255)
  static let practiceKeyboardDeep = Color(red: 28 / 255, green: 21 / 255, blue: 19 / 255)
  static let practiceIvoryHighlight = Color(red: 255 / 255, green: 253 / 255, blue: 248 / 255)
  static let practiceIvory = Color(red: 234 / 255, green: 223 / 255, blue: 214 / 255)

  static let recordReferenceDiameter: CGFloat = 236
  static let recordDiameter: CGFloat = 304
  static let recordScale = recordDiameter / recordReferenceDiameter
  static let recordSpacing: CGFloat = 294
  static let sideRecordScale: CGFloat = 0.80
  static let sideRecordWidthScale: CGFloat = 0.74
  static let crateMinimumHeight: CGFloat = 410

  static let windowMinimumHeight: CGFloat = 620
  static let windowIdealHeight: CGFloat = 720
  static let windowMaximumHeight: CGFloat = 860

  static let practiceOrnamentMinimumWidth: CGFloat = 360
  static let practiceOrnamentIdealWidth: CGFloat = 420
  static let practiceOrnamentMaximumWidth: CGFloat = 440
  static let practiceOrnamentContentPadding: CGFloat = 24
  static let practiceOrnamentCornerRadius: CGFloat = 34
  static let practiceCardCornerRadius: CGFloat = 22

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
