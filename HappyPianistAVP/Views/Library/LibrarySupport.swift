import Foundation
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
    static let recordSpacing: CGFloat = 24
    static let crateMinimumHeight: CGFloat = 410

    static let windowMinimumHeight: CGFloat = 620
    static let windowIdealHeight: CGFloat = 720
    static let windowMaximumHeight: CGFloat = 860

    static let liftMaximum: CGFloat = 72
    static let liftTrigger: CGFloat = 44
    static let deletionHoldSeconds = 2.0
    static let deletionHoldDuration: Duration = .seconds(deletionHoldSeconds)

    static let tonearmLength: CGFloat = 184
    static let tonearmPivotX: CGFloat = 264
    static let tonearmPivotY: CGFloat = -2.5
    static let armrestCenterX: CGFloat = 237.5
    static let armrestCenterY: CGFloat = 176

    static let ease = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.62)
    static let easeOut = Animation.timingCurve(0.16, 1, 0.30, 1, duration: 0.56)
}

struct LibraryRecordScrollPresentation: Equatable {
    let scale: CGFloat
    let opacity: Double
    let saturation: Double

    init(centerDistance: CGFloat) {
        let normalizedDistance = min(
            abs(centerDistance) / LibraryDesignTokens.recordDiameter,
            2
        )
        scale = max(0.64, 1 - normalizedDistance * 0.18)
        opacity = Double(max(0.42, 1 - normalizedDistance * 0.22))
        saturation = Double(max(0.72, 1 - normalizedDistance * 0.11))
    }
}

enum LibraryRecordScrollTapAction: Equatable {
    case togglePlayback
    case selectEntry
}

enum LibraryRecordScrollSelectionDecision {
    static func action(
        forTappedEntryID entryID: UUID,
        selectedEntryID: UUID?
    ) -> LibraryRecordScrollTapAction {
        entryID == selectedEntryID ? .togglePlayback : .selectEntry
    }

    static func selectionToCommit(
        scrollTargetID: UUID?,
        selectedEntryID: UUID?
    ) -> UUID? {
        guard let scrollTargetID, scrollTargetID != selectedEntryID else { return nil }
        return scrollTargetID
    }
}

enum LibraryVerticalDragIntentPolicy {
    static func isClearlyVertical(translation: CGSize) -> Bool {
        abs(translation.height) > abs(translation.width) * 1.5
    }
}

enum LibraryDeletionHoldPolicy {
    static func progress(for downwardDragTranslation: CGFloat) -> CGFloat {
        min(max(downwardDragTranslation / LibraryDesignTokens.liftMaximum, 0), 1)
    }

    static func isArmed(
        downwardDragTranslation: CGFloat,
        isBundled: Bool,
        allowsDestructiveActions: Bool
    ) -> Bool {
        isBundled == false
            && allowsDestructiveActions
            && downwardDragTranslation >= LibraryDesignTokens.liftTrigger
    }
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
