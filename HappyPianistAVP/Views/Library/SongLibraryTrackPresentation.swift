import Library
import SwiftUI

struct SongLibraryTrackPresentation {
    let title: String
    let subtitle: String
    let accentColor: Color

    init(entry: SongLibraryEntry, index: Int) {
        title = entry.displayName.replacing("_", with: " ")

        subtitle = entry.isBundled == true
            ? "内置曲目"
            : "导入于 \(entry.importedAt.formatted(date: .abbreviated, time: .omitted))"

        let palette: [Color] = [
            Color(red: 77 / 255, green: 127 / 255, blue: 116 / 255),
            Color(red: 197 / 255, green: 106 / 255, blue: 86 / 255),
            Color(red: 189 / 255, green: 148 / 255, blue: 82 / 255),
            Color(red: 138 / 255, green: 100 / 255, blue: 134 / 255),
            Color(red: 74 / 255, green: 102 / 255, blue: 140 / 255),
            Color(red: 142 / 255, green: 112 / 255, blue: 82 / 255),
        ]
        accentColor = palette[index % palette.count]
    }
}
