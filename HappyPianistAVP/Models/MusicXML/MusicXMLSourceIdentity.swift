import Foundation

struct MusicXMLSourceNoteID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let partID: String
    let sourceMeasureIndex: Int
    let sourceMeasureNumberToken: String?
    let staff: Int?
    let voice: Int?
    let sourceOrdinal: Int

    var description: String {
        [
            partID,
            String(sourceMeasureIndex),
            sourceMeasureNumberToken ?? "null",
            staff.map(String.init) ?? "null",
            voice.map(String.init) ?? "null",
            String(sourceOrdinal),
        ].joined(separator: ":")
    }
}
