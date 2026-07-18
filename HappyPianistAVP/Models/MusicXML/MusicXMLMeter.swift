import Foundation

struct MusicXMLMeter: Equatable, Hashable, Sendable {
    struct Component: Equatable, Hashable, Sendable {
        let beatGroups: [Int]
        let beatType: Int

        var beats: Int { beatGroups.reduce(0, +) }
        var displayText: String { "\(beatGroups.map(String.init).joined(separator: "+"))/\(beatType)" }
    }

    let components: [Component]
    let symbolToken: String?
    let isSenzaMisura: Bool
    let approximation: String?

    var displayText: String {
        if isSenzaMisura { return "senza misura" }
        return components.map(\.displayText).joined(separator: " + ")
    }

    var totalBeats: Int { components.reduce(0) { $0 + $1.beats } }
    var primaryBeatType: Int { components.first?.beatType ?? 4 }
}
