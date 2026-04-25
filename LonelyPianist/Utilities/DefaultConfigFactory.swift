import Foundation

enum DefaultConfigFactory {
    static func makeDefaultConfig(referenceDate: Date = .now) -> MappingConfig {
        let noteStart = 48
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let singleRules: [SingleKeyMappingRule] = characters.enumerated().map { index, character in
            let note = noteStart + index
            let keyCode = KeyStroke.keyCode(for: character) ?? 0
            return SingleKeyMappingRule(
                note: note,
                output: KeyStroke(keyCode: keyCode),
                velocityThreshold: 100
            )
        }

        let chordRules: [ChordMappingRule] = [
            ChordMappingRule(notes: [60, 64, 67], output: keyStroke("c", modifiers: [.command])),
            ChordMappingRule(notes: [62, 65, 69], output: keyStroke("v", modifiers: [.command])),
            ChordMappingRule(notes: [59, 62, 65], output: keyStroke("z", modifiers: [.command])),
        ]

        return MappingConfig(
            id: UUID(),
            updatedAt: referenceDate,
            payload: MappingConfigPayload(
                velocityEnabled: true,
                defaultVelocityThreshold: 100,
                singleKeyRules: singleRules,
                chordRules: chordRules
            )
        )
    }

    private static func keyStroke(_ character: Character, modifiers: KeyStrokeModifiers = []) -> KeyStroke {
        let keyCode = KeyStroke.keyCode(for: character) ?? 0
        return KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }
}
