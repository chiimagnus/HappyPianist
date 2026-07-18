import Foundation

struct MusicXMLDirectionSourceID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    let partID: String
    let sourceMeasureIndex: Int
    let sourceMeasureNumberToken: String?
    let sourceOrdinal: Int

    var description: String {
        [
            partID,
            String(sourceMeasureIndex),
            sourceMeasureNumberToken ?? "null",
            String(sourceOrdinal),
        ].joined(separator: ":")
    }
}
