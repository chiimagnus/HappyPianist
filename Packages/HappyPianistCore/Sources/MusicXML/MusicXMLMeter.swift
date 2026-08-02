import Foundation


public struct MusicXMLMeter: Equatable, Hashable, Sendable {
    public struct Component: Equatable, Hashable, Sendable {
        let beatGroups: [Int]
        let beatType: Int

        var beats: Int {
            beatGroups.reduce(0, +)
        }

        var displayText: String {
            "\(beatGroups.map(String.init).joined(separator: "+"))/\(beatType)"
        }
    }

    public let components: [Component]
    public let symbolToken: String?
    public let isSenzaMisura: Bool
    public let approximation: String?

    public var displayText: String {
        if isSenzaMisura { return "senza misura" }
        return components.map(\.displayText).joined(separator: " + ")
    }

    public var totalBeats: Int {
        components.reduce(0) { $0 + $1.beats }
    }

    public var primaryBeatType: Int {
        components.first?.beatType ?? 4
    }
}
