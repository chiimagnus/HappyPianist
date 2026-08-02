import Foundation


public struct MusicXMLDirectionSourceID: Codable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let partID: String
    public let sourceMeasureIndex: Int
    public let sourceMeasureNumberToken: String?
    public let sourceOrdinal: Int

    public var description: String {
        [
            partID,
            String(sourceMeasureIndex),
            sourceMeasureNumberToken ?? "null",
            String(sourceOrdinal),
        ].joined(separator: ":")
    }
}
