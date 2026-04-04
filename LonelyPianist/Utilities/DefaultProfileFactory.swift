import Foundation

enum DefaultProfileFactory {
    static func makeProfiles(referenceDate: Date = .now) -> [MappingProfile] {
        [
            makeDefaultQwertyProfile(referenceDate: referenceDate),
            makeCodingProfile(referenceDate: referenceDate)
        ]
    }

    private static func makeDefaultQwertyProfile(referenceDate: Date) -> MappingProfile {
        let noteStart = 48
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let singleRules: [SingleKeyMappingRule] = characters.enumerated().map { index, character in
            let note = noteStart + index
            return SingleKeyMappingRule(
                note: note,
                normalOutput: String(character),
                velocityThreshold: 100,
                highVelocityOutput: String(character).uppercased()
            )
        }

        let chordRules: [ChordMappingRule] = [
            ChordMappingRule(notes: [60, 64, 67], action: .keyCombo("cmd+c")),
            ChordMappingRule(notes: [62, 65, 69], action: .keyCombo("cmd+v")),
            ChordMappingRule(notes: [59, 62, 65], action: .keyCombo("cmd+z"))
        ]

        let melodyRules: [MelodyMappingRule] = [
            MelodyMappingRule(notes: [64, 64, 67], maxIntervalMilliseconds: 600, action: .text("hello ")),
            MelodyMappingRule(notes: [60, 62, 64, 67], maxIntervalMilliseconds: 500, action: .shortcut("Open Notion"))
        ]

        return MappingProfile(
            id: UUID(),
            name: "Default QWERTY",
            isBuiltIn: true,
            isActive: true,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            payload: MappingProfilePayload(
                velocityEnabled: true,
                defaultVelocityThreshold: 100,
                singleKeyRules: singleRules,
                chordRules: chordRules,
                melodyRules: melodyRules
            )
        )
    }

    private static func makeCodingProfile(referenceDate: Date) -> MappingProfile {
        let baseNotes = Array(60...75)
        let symbols = ["{", "}", "(", ")", "[", "]", ";", ":", "<", ">", "=", "+", "-", "_", "/", "*"]

        let singleRules: [SingleKeyMappingRule] = zip(baseNotes, symbols).map { note, symbol in
            SingleKeyMappingRule(
                note: note,
                normalOutput: symbol,
                velocityThreshold: 95,
                highVelocityOutput: symbol
            )
        }

        let chordRules: [ChordMappingRule] = [
            ChordMappingRule(notes: [60, 63, 67], action: .keyCombo("cmd+shift+4")),
            ChordMappingRule(notes: [62, 65, 69], action: .keyCombo("cmd+space")),
            ChordMappingRule(notes: [64, 67, 71], action: .keyCombo("cmd+k"))
        ]

        let melodyRules: [MelodyMappingRule] = [
            MelodyMappingRule(notes: [67, 69, 71], maxIntervalMilliseconds: 450, action: .text("func ")),
            MelodyMappingRule(notes: [71, 69, 67], maxIntervalMilliseconds: 450, action: .text("return "))
        ]

        return MappingProfile(
            id: UUID(),
            name: "Code Mode",
            isBuiltIn: true,
            isActive: false,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            payload: MappingProfilePayload(
                velocityEnabled: true,
                defaultVelocityThreshold: 95,
                singleKeyRules: singleRules,
                chordRules: chordRules,
                melodyRules: melodyRules
            )
        )
    }
}
