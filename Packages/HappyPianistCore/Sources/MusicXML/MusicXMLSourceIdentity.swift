import Foundation


public struct MusicXMLSourceNoteID: Codable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let partID: String
    public let sourceMeasureIndex: Int
    public let sourceMeasureNumberToken: String?
    public let staff: Int?
    public let voice: Int?
    public let sourceOrdinal: Int

    public init(
        partID: String,
        sourceMeasureIndex: Int,
        sourceMeasureNumberToken: String?,
        staff: Int?,
        voice: Int?,
        sourceOrdinal: Int
    ) {
        self.partID = partID
        self.sourceMeasureIndex = sourceMeasureIndex
        self.sourceMeasureNumberToken = sourceMeasureNumberToken
        self.staff = staff
        self.voice = voice
        self.sourceOrdinal = sourceOrdinal
    }

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
