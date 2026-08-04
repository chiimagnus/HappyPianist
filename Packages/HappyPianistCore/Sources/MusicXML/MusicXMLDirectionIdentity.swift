import Foundation


public struct MusicXMLDirectionSourceID: Codable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let partID: String
    public let sourceMeasureIndex: Int
    public let sourceMeasureNumberToken: String?
    public let sourceOrdinal: Int

    public init(
        partID: String,
        sourceMeasureIndex: Int,
        sourceMeasureNumberToken: String?,
        sourceOrdinal: Int
    ) {
        self.partID = partID
        self.sourceMeasureIndex = sourceMeasureIndex
        self.sourceMeasureNumberToken = sourceMeasureNumberToken
        self.sourceOrdinal = sourceOrdinal
    }

    public var description: String {
        [
            partID,
            String(sourceMeasureIndex),
            sourceMeasureNumberToken ?? "null",
            String(sourceOrdinal),
        ].joined(separator: ":")
    }
}
