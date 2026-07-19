import Foundation

enum MusicXMLPedalController: UInt8, Equatable, Sendable {
    case damper = 64
    case sostenuto = 66
    case soft = 67
}

struct MusicXMLControllerValue: Equatable, Sendable {
    static let off = MusicXMLControllerValue(percentage: 0, midiValue: 0)
    static let on = MusicXMLControllerValue(percentage: 100, midiValue: 127)

    let percentage: Decimal
    let midiValue: UInt8

    init?(percentage: Decimal) {
        guard percentage >= 0, percentage <= 100 else { return nil }
        self.percentage = percentage
        midiValue = UInt8((NSDecimalNumber(decimal: percentage).doubleValue * 1.27).rounded())
    }

    init?(musicXMLString: String) {
        let token = musicXMLString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch token {
        case "yes":
            self = .on
        case "no":
            self = .off
        default:
            guard let percentage = Decimal(
                string: token,
                locale: Locale(identifier: "en_US_POSIX")
            ) else { return nil }
            self.init(percentage: percentage)
        }
    }

    private init(percentage: Decimal, midiValue: UInt8) {
        self.percentage = percentage
        self.midiValue = midiValue
    }
}
