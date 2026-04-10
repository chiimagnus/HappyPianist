import Foundation

final class DefaultMappingEngine: MappingEngineProtocol {
    private var pressedNotes: Set<Int> = []
    private var triggeredChordRuleIDs: Set<UUID> = []

    func reset() {
        pressedNotes.removeAll(keepingCapacity: false)
        triggeredChordRuleIDs.removeAll(keepingCapacity: false)
    }

    func process(event: MIDIEvent, payload: MappingConfigPayload) -> [ResolvedKeyStroke] {
        switch event.type {
        case .noteOn(let note, let velocity):
            return processNoteOn(note: note, velocity: velocity, payload: payload)
        case .noteOff(let note, _):
            processNoteOff(note: note, payload: payload)
            return []
        case .controlChange:
            return []
        }
    }

    private func processNoteOn(
        note: Int,
        velocity: Int,
        payload: MappingConfigPayload
    ) -> [ResolvedKeyStroke] {
        pressedNotes.insert(note)

        var resolved: [ResolvedKeyStroke] = []

        if let output = resolveSingleKeyOutput(note: note, velocity: velocity, payload: payload) {
            resolved.append(
                ResolvedKeyStroke(
                    triggerType: .singleKey,
                    keyStroke: output,
                    sourceDescription: MIDINote(note).name
                )
            )
        }

        resolved.append(contentsOf: resolveChordActions(payload: payload))
        return resolved
    }

    private func resolveSingleKeyOutput(note: Int, velocity: Int, payload: MappingConfigPayload) -> KeyStroke? {
        guard let rule = payload.singleKeyRules.first(where: { $0.note == note }) else {
            return nil
        }

        let baseOutput = KeyStroke(keyCode: rule.output.keyCode)

        guard payload.velocityEnabled else {
            return baseOutput
        }

        let threshold = rule.velocityThreshold ?? payload.defaultVelocityThreshold
        if velocity >= threshold {
            return baseOutput.adding(.shift)
        }

        return baseOutput
    }

    private func processNoteOff(note: Int, payload: MappingConfigPayload) {
        pressedNotes.remove(note)

        let rulesByID = Dictionary(uniqueKeysWithValues: payload.chordRules.map { ($0.id, $0) })
        triggeredChordRuleIDs = triggeredChordRuleIDs.filter { ruleID in
            guard let rule = rulesByID[ruleID] else { return false }
            let requiredNotes = Set(rule.notes)
            return requiredNotes.isSubset(of: pressedNotes)
        }
    }

    private func resolveChordActions(payload: MappingConfigPayload) -> [ResolvedKeyStroke] {
        guard !pressedNotes.isEmpty else { return [] }

        var actions: [ResolvedKeyStroke] = []

        for rule in payload.chordRules {
            let requiredNotes = Set(rule.notes)
            guard !requiredNotes.isEmpty else { continue }
            guard requiredNotes == pressedNotes else { continue }
            guard !triggeredChordRuleIDs.contains(rule.id) else { continue }

            triggeredChordRuleIDs.insert(rule.id)
            let label = rule.notes.map { MIDINote($0).name }.joined(separator: "+")
            actions.append(
                ResolvedKeyStroke(
                    triggerType: .chord,
                    keyStroke: rule.output,
                    sourceDescription: label
                )
            )
        }

        return actions
    }
}
