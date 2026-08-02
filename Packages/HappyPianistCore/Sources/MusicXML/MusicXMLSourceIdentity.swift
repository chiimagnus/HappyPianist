import Foundation


public struct MusicXMLSourceNoteID: Codable, Equatable, Hashable, CustomStringConvertible {
    public let partID: String
    public let sourceMeasureIndex: Int
    public let sourceMeasureNumberToken: String?
    public let staff: Int?
    public let voice: Int?
    public let sourceOrdinal: Int

    public var description: String {
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
