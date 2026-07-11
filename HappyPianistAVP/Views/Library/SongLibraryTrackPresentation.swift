import SwiftUI

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
