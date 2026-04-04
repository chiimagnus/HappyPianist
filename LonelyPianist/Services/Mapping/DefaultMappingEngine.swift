import Foundation

final class DefaultMappingEngine: MappingEngineProtocol {
    private var pressedNotes: Set<Int> = []
    private var triggeredChordRuleIDs: Set<UUID> = []
    private var melodyHistory: [(note: Int, timestamp: Date)] = []
    private var lastMelodyTriggerAt: [UUID: Date] = [:]

    private let melodyCooldownSeconds: TimeInterval = 0.15
    private let historyWindowSeconds: TimeInterval = 12

    func reset() {
        pressedNotes.removeAll(keepingCapacity: false)
        triggeredChordRuleIDs.removeAll(keepingCapacity: false)
        melodyHistory.removeAll(keepingCapacity: false)
        lastMelodyTriggerAt.removeAll(keepingCapacity: false)
    }

    func process(event: MIDIEvent, profile: MappingProfile) -> [ResolvedMappingAction] {
        switch event.type {
        case .noteOn:
            return processNoteOn(event: event, profile: profile)
        case .noteOff:
            processNoteOff(event: event, profile: profile)
            return []
        }
    }

    private func processNoteOn(event: MIDIEvent, profile: MappingProfile) -> [ResolvedMappingAction] {
        pressedNotes.insert(event.note)

        var resolved: [ResolvedMappingAction] = []

        if let output = resolveSingleKeyOutput(note: event.note, velocity: event.velocity, profile: profile),
           !output.isEmpty {
            resolved.append(
                ResolvedMappingAction(
                    triggerType: .singleKey,
                    action: .text(output),
                    sourceDescription: MIDINote(event.note).name
                )
            )
        }

        resolved.append(contentsOf: resolveChordActions(profile: profile))
        resolved.append(contentsOf: resolveMelodyActions(event: event, profile: profile))

        return resolved
    }

    private func resolveSingleKeyOutput(note: Int, velocity: Int, profile: MappingProfile) -> String? {
        guard let rule = profile.payload.singleKeyRules.first(where: { $0.note == note }) else {
            return nil
        }

        guard profile.payload.velocityEnabled else {
            return rule.normalOutput
        }

        let threshold = rule.velocityThreshold ?? profile.payload.defaultVelocityThreshold
        if velocity >= threshold,
           let highOutput = rule.highVelocityOutput,
           !highOutput.isEmpty {
            return highOutput
        }

        return rule.normalOutput
    }

    private func processNoteOff(event: MIDIEvent, profile: MappingProfile) {
        pressedNotes.remove(event.note)

        let rulesByID = Dictionary(uniqueKeysWithValues: profile.payload.chordRules.map { ($0.id, $0) })
        triggeredChordRuleIDs = triggeredChordRuleIDs.filter { ruleID in
            guard let rule = rulesByID[ruleID] else { return false }
            let requiredNotes = Set(rule.notes)
            return requiredNotes.isSubset(of: pressedNotes)
        }
    }

    private func resolveChordActions(profile: MappingProfile) -> [ResolvedMappingAction] {
        guard !pressedNotes.isEmpty else { return [] }

        var actions: [ResolvedMappingAction] = []

        for rule in profile.payload.chordRules {
            let requiredNotes = Set(rule.notes)
            guard !requiredNotes.isEmpty else { continue }
            guard requiredNotes == pressedNotes else { continue }
            guard !triggeredChordRuleIDs.contains(rule.id) else { continue }

            triggeredChordRuleIDs.insert(rule.id)
            let label = rule.notes.map { MIDINote($0).name }.joined(separator: "+")
            actions.append(
                ResolvedMappingAction(
                    triggerType: .chord,
                    action: rule.action,
                    sourceDescription: label
                )
            )
        }

        return actions
    }

    private func resolveMelodyActions(event: MIDIEvent, profile: MappingProfile) -> [ResolvedMappingAction] {
        melodyHistory.append((note: event.note, timestamp: event.timestamp))
        trimMelodyHistory(reference: event.timestamp)

        var actions: [ResolvedMappingAction] = []

        for rule in profile.payload.melodyRules {
            guard matches(rule: rule, timestamp: event.timestamp) else { continue }

            if let last = lastMelodyTriggerAt[rule.id],
               event.timestamp.timeIntervalSince(last) < melodyCooldownSeconds {
                continue
            }

            lastMelodyTriggerAt[rule.id] = event.timestamp
            let label = rule.notes.map { MIDINote($0).name }.joined(separator: " ")

            actions.append(
                ResolvedMappingAction(
                    triggerType: .melody,
                    action: rule.action,
                    sourceDescription: label
                )
            )
        }

        return actions
    }

    private func trimMelodyHistory(reference: Date) {
        melodyHistory.removeAll { reference.timeIntervalSince($0.timestamp) > historyWindowSeconds }

        let maxCount = 64
        if melodyHistory.count > maxCount {
            melodyHistory.removeFirst(melodyHistory.count - maxCount)
        }
    }

    private func matches(rule: MelodyMappingRule, timestamp: Date) -> Bool {
        let ruleNotes = rule.notes
        guard !ruleNotes.isEmpty else { return false }
        guard melodyHistory.count >= ruleNotes.count else { return false }

        let recentSlice = melodyHistory.suffix(ruleNotes.count)
        let recent = Array(recentSlice)

        for index in recent.indices {
            guard recent[index].note == ruleNotes[index] else {
                return false
            }

            if index > 0 {
                let delta = recent[index].timestamp.timeIntervalSince(recent[index - 1].timestamp)
                let maxInterval = TimeInterval(rule.maxIntervalMilliseconds) / 1000
                guard delta <= maxInterval else {
                    return false
                }
            }
        }

        guard let first = recent.first else { return false }
        let totalDuration = timestamp.timeIntervalSince(first.timestamp)
        let maxTotalDuration = TimeInterval(rule.maxIntervalMilliseconds * max(1, ruleNotes.count - 1)) / 1000
        return totalDuration <= maxTotalDuration
    }
}
