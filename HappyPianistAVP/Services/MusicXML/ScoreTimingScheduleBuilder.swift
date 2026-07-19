import Foundation

struct ScoreTimingScheduleBuilder {
    func build(
        notes: [MusicXMLNoteEvent],
        performanceTimingEnabled: Bool = false,
        graceEnabled: Bool = true,
        logicalInstruments: [MusicXMLLogicalInstrument] = [],
        arpeggiateEnabled: Bool = false,
        interpretationProfile: MusicXMLInterpretationProfile = .generic
    ) -> ScoreTimingSchedule {
        var entries = notes.enumerated().map { index, note in
            MutableEntry(noteIndex: index, note: note, performanceTimingEnabled: performanceTimingEnabled)
        }
        let graceGroups = graceEnabled ? makeGraceGroups(notes: notes) : []

        applyMakeTime(
            groups: graceGroups,
            notes: notes,
            entries: &entries
        )
        applyStealTime(
            groups: graceGroups,
            notes: notes,
            entries: &entries
        )
        if arpeggiateEnabled {
            applyArpeggio(
                notes: notes,
                logicalInstruments: logicalInstruments,
                entries: &entries
            )
        }
        applyArticulation(
            notes: notes,
            profile: interpretationProfile,
            entries: &entries
        )
        applySlurs(
            notes: notes,
            profile: interpretationProfile,
            entries: &entries
        )
        let directives = applyPhraseBreaks(
            notes: notes,
            profile: interpretationProfile,
            entries: &entries
        )
        // ponytail: fermata stays a single downstream pause directive; timing entries never stretch it again.
        let entryValues = entries.map(\.value)
        let ornamentSchedule = MusicXMLOrnamentScheduler().schedule(
            notes: notes,
            timingEntries: entryValues,
            interpretationProfile: interpretationProfile
        )

        return ScoreTimingSchedule(
            entries: entryValues,
            directives: directives,
            generatedNotes: ornamentSchedule.generatedNotes,
            notationResolutions: ornamentSchedule.resolutions
        )
    }
}

private extension ScoreTimingScheduleBuilder {
    struct GraceLane: Hashable {
        let partID: String
        let staff: Int
        let voice: Int
    }

    struct GraceGroupKey: Hashable {
        let lane: GraceLane
        let tick: Int
    }

    struct GraceGroup {
        let key: GraceGroupKey
        let noteIndices: [Int]
    }

    struct MakeTimeGroup {
        let group: GraceGroup
        let durationTicks: Int
    }

    struct SlurKey: Hashable {
        let lane: GraceLane
        let numberToken: String
    }

    struct ActiveSlur {
        let startPosition: Int
        let sourceID: MusicXMLPerformanceNotationSourceID?
    }

    struct ArpeggioGroupKey: Hashable {
        let logicalInstrumentID: String
        let performedTick: Int
        let numberToken: String
        let sourceMeasureIndex: Int
        let sourceTick: Int
        let occurrenceIndex: Int
    }

    struct ArpeggioCandidate {
        let noteIndex: Int
        let midiNote: Int
        let durationTicks: Int
        let arpeggiate: MusicXMLArpeggiate
    }

    struct MutableEntry {
        let noteIndex: Int
        let sourceNoteID: MusicXMLSourceNoteID?
        let performedNoteID: MusicXMLPerformedNoteID?
        let writtenOnTick: Int
        let writtenOffTick: Int
        var performedOnTick: Int
        var performedOffTick: Int
        var onsetOffsetTicks: Int
        var releaseOffsetTicks: Int
        var releasePolicy: ScoreTimingReleasePolicy
        var provenance: [ScoreTimingProvenance]

        init(noteIndex: Int, note: MusicXMLNoteEvent, performanceTimingEnabled: Bool) {
            let writtenOnTick = max(0, note.tick)
            let writtenOffTick = max(writtenOnTick, writtenOnTick + max(0, note.durationTicks))
            let onsetOffsetTicks = performanceTimingEnabled ? (note.attackTicks ?? 0) : 0
            let releaseOffsetTicks = performanceTimingEnabled ? (note.releaseTicks ?? 0) : 0
            let performedOnTick = max(0, writtenOnTick + onsetOffsetTicks)
            let performedOffTick = max(performedOnTick, writtenOffTick + releaseOffsetTicks)
            let usesPerformanceOffsets = onsetOffsetTicks != 0 || releaseOffsetTicks != 0

            self.noteIndex = noteIndex
            sourceNoteID = note.sourceID
            performedNoteID = note.performedID
            self.writtenOnTick = writtenOnTick
            self.writtenOffTick = writtenOffTick
            self.performedOnTick = performedOnTick
            self.performedOffTick = performedOffTick
            self.onsetOffsetTicks = onsetOffsetTicks
            self.releaseOffsetTicks = releaseOffsetTicks
            releasePolicy = usesPerformanceOffsets ? .performanceOffsets : .writtenDuration
            provenance = usesPerformanceOffsets ? [.score, .performanceOffset] : [.score]
        }

        var value: ScoreTimingEntry {
            ScoreTimingEntry(
                noteIndex: noteIndex,
                sourceNoteID: sourceNoteID,
                performedNoteID: performedNoteID,
                writtenOnTick: writtenOnTick,
                writtenOffTick: writtenOffTick,
                performedOnTick: performedOnTick,
                performedOffTick: performedOffTick,
                onsetOffsetTicks: onsetOffsetTicks,
                releaseOffsetTicks: releaseOffsetTicks,
                releasePolicy: releasePolicy,
                provenance: provenance
            )
        }

        mutating func shift(by ticks: Int, provenance timingProvenance: ScoreTimingProvenance) {
            guard ticks != 0 else { return }
            performedOnTick = max(0, performedOnTick + ticks)
            performedOffTick = max(performedOnTick, performedOffTick + ticks)
            onsetOffsetTicks = performedOnTick - writtenOnTick
            releaseOffsetTicks = performedOffTick - writtenOffTick
            releasePolicy = .graceMakeTime
            appendProvenance(timingProvenance)
        }

        mutating func setInterval(
            onTick: Int,
            offTick: Int,
            policy: ScoreTimingReleasePolicy,
            timingProvenance: ScoreTimingProvenance
        ) {
            performedOnTick = max(0, onTick)
            performedOffTick = max(performedOnTick, offTick)
            onsetOffsetTicks = performedOnTick - writtenOnTick
            releaseOffsetTicks = performedOffTick - writtenOffTick
            releasePolicy = policy
            appendProvenance(timingProvenance)
        }

        mutating func delayOnset(
            by ticks: Int,
            policy: ScoreTimingReleasePolicy,
            timingProvenance: ScoreTimingProvenance
        ) {
            guard ticks > 0 else { return }
            performedOnTick = min(performedOffTick, performedOnTick + ticks)
            onsetOffsetTicks = performedOnTick - writtenOnTick
            releasePolicy = policy
            appendProvenance(timingProvenance)
        }

        mutating func shortenRelease(
            by ticks: Int,
            policy: ScoreTimingReleasePolicy,
            timingProvenance: ScoreTimingProvenance
        ) {
            guard ticks > 0 else { return }
            performedOffTick = max(performedOnTick, performedOffTick - ticks)
            releaseOffsetTicks = performedOffTick - writtenOffTick
            releasePolicy = policy
            appendProvenance(timingProvenance)
        }

        mutating func appendProvenance(_ timingProvenance: ScoreTimingProvenance) {
            if provenance.contains(timingProvenance) == false {
                provenance.append(timingProvenance)
            }
        }
    }

    func makeGraceGroups(notes: [MusicXMLNoteEvent]) -> [GraceGroup] {
        var indicesByKey: [GraceGroupKey: [Int]] = [:]
        for (index, note) in notes.enumerated() where note.isGrace && note.isRest == false {
            let key = GraceGroupKey(
                lane: GraceLane(
                    partID: note.partID,
                    staff: note.staff ?? 1,
                    voice: note.voice ?? 1
                ),
                tick: note.tick
            )
            indicesByKey[key, default: []].append(index)
        }

        return indicesByKey.map { key, indices in
            GraceGroup(key: key, noteIndices: indices.sorted())
        }.sorted { lhs, rhs in
            if lhs.key.tick != rhs.key.tick { return lhs.key.tick < rhs.key.tick }
            return (lhs.noteIndices.first ?? 0) < (rhs.noteIndices.first ?? 0)
        }
    }

    func applyMakeTime(
        groups: [GraceGroup],
        notes: [MusicXMLNoteEvent],
        entries: inout [MutableEntry]
    ) {
        let makeTimeGroups = groups.compactMap { group -> MakeTimeGroup? in
            let explicitDurations = group.noteIndices.compactMap { notes[$0].graceMakeTimeTicks }.filter { $0 > 0 }
            guard explicitDurations.isEmpty == false else { return nil }

            let requestedDuration: Int
            if explicitDurations.count == group.noteIndices.count {
                requestedDuration = explicitDurations.reduce(0, +)
            } else {
                requestedDuration = explicitDurations[0]
            }
            return MakeTimeGroup(
                group: group,
                durationTicks: max(group.noteIndices.count, requestedDuration)
            )
        }
        guard makeTimeGroups.isEmpty == false else { return }

        var insertionByTick: [Int: Int] = [:]
        for item in makeTimeGroups {
            insertionByTick[item.group.key.tick] = max(
                insertionByTick[item.group.key.tick] ?? 0,
                item.durationTicks
            )
        }
        let insertionTicks = insertionByTick.keys.sorted()

        for index in notes.indices {
            let note = notes[index]
            let shift = insertionTicks.reduce(into: 0) { result, tick in
                if tick < note.tick || (tick == note.tick && note.isGrace == false) {
                    result += insertionByTick[tick] ?? 0
                }
            }
            entries[index].shift(by: shift, provenance: .grace(kind: .makeTime))
        }

        for item in makeTimeGroups {
            let earlierShift = insertionTicks.reduce(into: 0) { result, tick in
                if tick < item.group.key.tick {
                    result += insertionByTick[tick] ?? 0
                }
            }
            let startTick = max(0, item.group.key.tick + earlierShift)
            setGraceIntervals(
                noteIndices: item.group.noteIndices,
                startTick: startTick,
                durationTicks: item.durationTicks,
                policy: .graceMakeTime,
                provenance: .grace(kind: .makeTime),
                notes: notes,
                entries: &entries
            )
        }
    }

    func applyStealTime(
        groups: [GraceGroup],
        notes: [MusicXMLNoteEvent],
        entries: inout [MutableEntry]
    ) {
        for group in groups {
            let hasMakeTime = group.noteIndices.contains { notes[$0].graceMakeTimeTicks != nil }
            if hasMakeTime {
                let hasStealTime = group.noteIndices.contains {
                    notes[$0].graceStealTimePrevious != nil || notes[$0].graceStealTimeFollowing != nil
                }
                if hasStealTime {
                    for index in group.noteIndices {
                        entries[index].appendProvenance(.approximation(reason: "grace-make-time-overrides-steal-time"))
                    }
                }
                continue
            }

            let previousFraction = group.noteIndices.compactMap { notes[$0].graceStealTimePrevious }.first
            var followingFraction = group.noteIndices.compactMap { notes[$0].graceStealTimeFollowing }.first
            var usedDefaultFollowing = false
            if previousFraction == nil, followingFraction == nil {
                followingFraction = 0.25
                usedDefaultFollowing = true
            }

            let previousIndices = previousRegularNoteIndices(before: group, notes: notes)
            let followingIndices = followingRegularNoteIndices(after: group, notes: notes)

            let previousTicks = stolenTicks(
                fraction: previousFraction,
                referenceDuration: previousIndices.first.map { notes[$0].durationTicks }
            )
            let followingTicks = stolenTicks(
                fraction: followingFraction,
                referenceDuration: followingIndices.first.map { notes[$0].durationTicks }
            )

            if previousFraction != nil, previousTicks == 0 {
                markApproximation(
                    "grace-steal-previous-missing-anchor",
                    noteIndices: group.noteIndices,
                    entries: &entries
                )
            }
            if followingFraction != nil, followingTicks == 0 {
                markApproximation(
                    "grace-steal-following-missing-anchor",
                    noteIndices: group.noteIndices,
                    entries: &entries
                )
            }

            if usedDefaultFollowing {
                markApproximation(
                    "grace-default-steal-following-25-percent",
                    noteIndices: group.noteIndices,
                    entries: &entries
                )
            }

            let totalTicks = previousTicks + followingTicks
            guard totalTicks > 0 else {
                for index in group.noteIndices where notes[index].graceSlash {
                    entries[index].appendProvenance(.approximation(reason: "grace-slash-does-not-define-duration"))
                }
                continue
            }

            let kind: ScoreGraceTimingKind
            let policy: ScoreTimingReleasePolicy
            if previousTicks > 0, followingTicks > 0 {
                kind = .stealPreviousAndFollowing
                policy = .graceStealPreviousAndFollowing
            } else if previousTicks > 0 {
                kind = .stealPrevious
                policy = .graceStealPrevious
            } else {
                kind = .stealFollowing
                policy = .graceStealFollowing
            }
            let timingProvenance = ScoreTimingProvenance.grace(kind: kind)

            for index in previousIndices {
                entries[index].shortenRelease(
                    by: previousTicks,
                    policy: .graceStealPrevious,
                    timingProvenance: .grace(kind: .stealPrevious)
                )
            }
            for index in followingIndices {
                entries[index].delayOnset(
                    by: followingTicks,
                    policy: .graceStealFollowing,
                    timingProvenance: .grace(kind: .stealFollowing)
                )
            }

            let anchorTick = group.noteIndices.first.map { entries[$0].performedOnTick } ?? group.key.tick
            setGraceIntervals(
                noteIndices: group.noteIndices,
                startTick: max(0, anchorTick - previousTicks),
                durationTicks: totalTicks,
                policy: policy,
                provenance: timingProvenance,
                notes: notes,
                entries: &entries
            )

        }
    }

    func applyArpeggio(
        notes: [MusicXMLNoteEvent],
        logicalInstruments: [MusicXMLLogicalInstrument],
        entries: inout [MutableEntry]
    ) {
        let instrumentIDByPartID = logicalInstruments.reduce(into: [String: String]()) { result, instrument in
            for partID in instrument.memberPartIDs where result[partID] == nil {
                result[partID] = instrument.id
            }
        }
        var candidatesByGroup: [ArpeggioGroupKey: [ArpeggioCandidate]] = [:]

        for index in notes.indices {
            let note = notes[index]
            guard note.isRest == false,
                  note.isGrace == false,
                  let midiNote = note.midiNote,
                  let arpeggiate = note.arpeggiate
            else {
                continue
            }

            let key = ArpeggioGroupKey(
                logicalInstrumentID: instrumentIDByPartID[note.partID] ?? "part:\(note.partID)",
                performedTick: entries[index].performedOnTick,
                numberToken: arpeggiate.normalizedNumberToken,
                sourceMeasureIndex: note.sourceID?.sourceMeasureIndex ?? note.measureNumber,
                sourceTick: note.tick,
                occurrenceIndex: note.performedOccurrenceIndex
            )
            candidatesByGroup[key, default: []].append(
                ArpeggioCandidate(
                    noteIndex: index,
                    midiNote: midiNote,
                    durationTicks: max(0, entries[index].performedOffTick - entries[index].performedOnTick),
                    arpeggiate: arpeggiate
                )
            )
        }

        for (key, candidates) in candidatesByGroup {
            guard candidates.isEmpty == false else { continue }
            let explicitDirections = Set(candidates.compactMap { $0.arpeggiate.direction })
            let direction = explicitDirections.sorted { $0.rawValue < $1.rawValue }.first ?? .up
            let provenance = ScoreTimingProvenance.arpeggio(
                numberToken: key.numberToken,
                direction: direction
            )

            if explicitDirections.count > 1 {
                for candidate in candidates {
                    entries[candidate.noteIndex].appendProvenance(
                        .approximation(reason: "arpeggio-conflicting-directions-defaulted-\(direction.rawValue)")
                    )
                }
            }
            for candidate in candidates where candidate.arpeggiate.directionToken != nil && candidate.arpeggiate.direction == nil {
                entries[candidate.noteIndex].appendProvenance(
                    .approximation(reason: "arpeggio-unsupported-direction-defaulted-up")
                )
            }

            let ordered = candidates.sorted { lhs, rhs in
                if lhs.midiNote != rhs.midiNote {
                    return direction == .down ? lhs.midiNote > rhs.midiNote : lhs.midiNote < rhs.midiNote
                }
                return lhs.noteIndex < rhs.noteIndex
            }
            guard ordered.count > 1 else {
                entries[ordered[0].noteIndex].appendProvenance(provenance)
                continue
            }

            let shortestDuration = ordered.map(\.durationTicks).filter { $0 > 0 }.min() ?? 0
            guard shortestDuration > 1 else {
                for candidate in ordered {
                    entries[candidate.noteIndex].appendProvenance(
                        .approximation(reason: "arpeggio-insufficient-duration")
                    )
                }
                continue
            }

            let totalSpreadTicks = max(
                1,
                min(shortestDuration - 1, min(480 / 16, shortestDuration / 4))
            )
            let stepTicks = max(1, totalSpreadTicks / (ordered.count - 1))
            var offsetTicks = 0
            for (position, candidate) in ordered.enumerated() {
                entries[candidate.noteIndex].delayOnset(
                    by: offsetTicks,
                    policy: .arpeggio,
                    timingProvenance: provenance
                )
                if position < ordered.count - 1 {
                    offsetTicks = min(totalSpreadTicks, offsetTicks + stepTicks)
                }
            }
        }
    }

    func applyArticulation(
        notes: [MusicXMLNoteEvent],
        profile: MusicXMLInterpretationProfile,
        entries: inout [MutableEntry]
    ) {
        for index in notes.indices where notes[index].isGrace == false {
            guard profile.hasDurationRule(for: notes[index].articulations) else { continue }
            let multiplier = profile.durationMultiplier(for: notes[index].articulations)
            let rawDuration = max(0, entries[index].performedOffTick - entries[index].performedOnTick)
            guard rawDuration > 0 else { continue }
            let adjustedDuration = min(
                rawDuration,
                max(1, Int((Double(rawDuration) * multiplier).rounded()))
            )
            entries[index].setInterval(
                onTick: entries[index].performedOnTick,
                offTick: entries[index].performedOnTick + adjustedDuration,
                policy: .interpretationProfile,
                timingProvenance: .interpretationProfile(id: profile.id)
            )
        }
    }

    func applySlurs(
        notes: [MusicXMLNoteEvent],
        profile: MusicXMLInterpretationProfile,
        entries: inout [MutableEntry]
    ) {
        let playableIndices = notes.indices.filter { index in
            notes[index].isRest == false && notes[index].isGrace == false
        }
        let indicesByLane = Dictionary(grouping: playableIndices) { lane(for: notes[$0]) }

        for (lane, indices) in indicesByLane {
            let ordered = indices.sorted { lhs, rhs in
                if entries[lhs].performedOnTick != entries[rhs].performedOnTick {
                    return entries[lhs].performedOnTick < entries[rhs].performedOnTick
                }
                return lhs < rhs
            }
            var activeByNumber: [String: ActiveSlur] = [:]

            for (position, noteIndex) in ordered.enumerated() {
                for slur in notes[noteIndex].slurs {
                    let numberToken = normalizedNumberToken(slur.numberToken)
                    let key = SlurKey(lane: lane, numberToken: numberToken)
                    switch slur.typeToken?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "start":
                        if let existing = activeByNumber[numberToken] {
                            markApproximation(
                                "slur-restarted-before-stop-\(key.numberToken)",
                                noteIndices: [ordered[existing.startPosition], noteIndex],
                                entries: &entries
                            )
                        }
                        activeByNumber[numberToken] = ActiveSlur(
                            startPosition: position,
                            sourceID: slur.sourceID
                        )
                    case "continue":
                        if activeByNumber[numberToken] == nil {
                            entries[noteIndex].appendProvenance(
                                .approximation(reason: "slur-continue-without-start-\(key.numberToken)")
                            )
                        }
                    case "stop":
                        guard let active = activeByNumber.removeValue(forKey: numberToken) else {
                            entries[noteIndex].appendProvenance(
                                .approximation(reason: "slur-stop-without-start-\(key.numberToken)")
                            )
                            continue
                        }
                        connectSlur(
                            noteIndices: Array(ordered[active.startPosition...position]),
                            sourceID: active.sourceID ?? slur.sourceID,
                            profile: profile,
                            notes: notes,
                            entries: &entries
                        )
                    default:
                        entries[noteIndex].appendProvenance(
                            .approximation(reason: "slur-missing-or-unsupported-type")
                        )
                    }
                }
            }

            for (numberToken, active) in activeByNumber {
                entries[ordered[active.startPosition]].appendProvenance(
                    .approximation(reason: "slur-start-without-stop-\(numberToken)")
                )
            }
        }
    }

    func connectSlur(
        noteIndices: [Int],
        sourceID: MusicXMLPerformanceNotationSourceID?,
        profile: MusicXMLInterpretationProfile,
        notes: [MusicXMLNoteEvent],
        entries: inout [MutableEntry]
    ) {
        guard noteIndices.count >= 2 else { return }
        let provenance = ScoreTimingProvenance.performanceNotation(
            kind: .slur,
            sourceID: sourceID,
            profileID: profile.id
        )

        for (offset, noteIndex) in noteIndices.dropLast().enumerated() {
            let currentOnTick = entries[noteIndex].performedOnTick
            guard let nextIndex = noteIndices[(offset + 1)...].first(where: {
                entries[$0].performedOnTick > currentOnTick
            }) else {
                continue
            }
            let nextOnTick = entries[nextIndex].performedOnTick
            guard nextOnTick > currentOnTick else { continue }

            if notes[noteIndex].startsTie || notes[noteIndex].stopsTie {
                entries[noteIndex].appendProvenance(provenance)
                entries[noteIndex].appendProvenance(
                    .approximation(reason: "slur-release-deferred-to-tie")
                )
                continue
            }
            let shortArticulations: Set<MusicXMLArticulation> = [
                .staccatissimo, .staccato, .detachedLegato, .marcato,
            ]
            if notes[noteIndex].articulations.isDisjoint(with: shortArticulations) == false {
                entries[noteIndex].appendProvenance(provenance)
                entries[noteIndex].appendProvenance(
                    .approximation(reason: "slur-conflicts-with-short-articulation")
                )
                continue
            }

            entries[noteIndex].setInterval(
                onTick: currentOnTick,
                offTick: nextOnTick,
                policy: .slurLegato,
                timingProvenance: provenance
            )
        }
    }

    func applyPhraseBreaks(
        notes: [MusicXMLNoteEvent],
        profile: MusicXMLInterpretationProfile,
        entries: inout [MutableEntry]
    ) -> [ScoreTimingDirective] {
        var caesuraByTick: [Int: ScoreTimingDirective] = [:]

        for index in notes.indices where notes[index].isRest == false && notes[index].isGrace == false {
            for notation in notes[index].performanceNotations {
                let provenance = ScoreTimingProvenance.performanceNotation(
                    kind: notation.kind,
                    sourceID: notation.sourceID,
                    profileID: profile.id
                )
                switch notation.kind {
                case .breathMark:
                    let available = max(0, entries[index].performedOffTick - entries[index].performedOnTick - 1)
                    let gapTicks = min(max(0, profile.breathGapTicks), available)
                    if gapTicks > 0 {
                        entries[index].shortenRelease(
                            by: gapTicks,
                            policy: .breathGap,
                            timingProvenance: provenance
                        )
                    } else {
                        entries[index].appendProvenance(provenance)
                        entries[index].appendProvenance(
                            .approximation(reason: "breath-gap-insufficient-duration")
                        )
                    }
                case .caesura:
                    let tick = entries[index].performedOffTick
                    let directive = ScoreTimingDirective(
                        kind: .caesuraPause,
                        tick: tick,
                        durationTicks: max(1, profile.caesuraPauseTicks),
                        sourceNotationID: notation.sourceID,
                        interpretationProfileID: profile.id
                    )
                    if caesuraByTick[tick] == nil {
                        caesuraByTick[tick] = directive
                    }
                    entries[index].appendProvenance(provenance)
                default:
                    continue
                }
            }
        }

        return caesuraByTick.values.sorted { lhs, rhs in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    func normalizedNumberToken(_ token: String?) -> String {
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), token.isEmpty == false else {
            return "1"
        }
        return token
    }

    func previousRegularNoteIndices(
        before group: GraceGroup,
        notes: [MusicXMLNoteEvent]
    ) -> [Int] {
        let candidates = notes.indices.filter { index in
            let note = notes[index]
            return note.isRest == false
                && note.isGrace == false
                && lane(for: note) == group.key.lane
                && note.tick < group.key.tick
        }
        guard let onset = candidates.map({ notes[$0].tick }).max() else { return [] }
        return candidates.filter { notes[$0].tick == onset }
    }

    func followingRegularNoteIndices(
        after group: GraceGroup,
        notes: [MusicXMLNoteEvent]
    ) -> [Int] {
        let candidates = notes.indices.filter { index in
            let note = notes[index]
            return note.isRest == false
                && note.isGrace == false
                && lane(for: note) == group.key.lane
                && note.tick >= group.key.tick
        }
        guard let onset = candidates.map({ notes[$0].tick }).min() else { return [] }
        return candidates.filter { notes[$0].tick == onset }
    }

    func lane(for note: MusicXMLNoteEvent) -> GraceLane {
        GraceLane(partID: note.partID, staff: note.staff ?? 1, voice: note.voice ?? 1)
    }

    func stolenTicks(fraction: Double?, referenceDuration: Int?) -> Int {
        guard let fraction, fraction > 0,
              let referenceDuration, referenceDuration > 1
        else {
            return 0
        }
        return max(
            1,
            min(referenceDuration - 1, Int((Double(referenceDuration) * fraction).rounded()))
        )
    }

    func setGraceIntervals(
        noteIndices: [Int],
        startTick: Int,
        durationTicks: Int,
        policy: ScoreTimingReleasePolicy,
        provenance: ScoreTimingProvenance,
        notes: [MusicXMLNoteEvent],
        entries: inout [MutableEntry]
    ) {
        let durations = partition(durationTicks: durationTicks, count: noteIndices.count)
        var cursor = max(0, startTick)
        for (offset, noteIndex) in noteIndices.enumerated() {
            let duration = durations[offset]
            entries[noteIndex].setInterval(
                onTick: cursor,
                offTick: cursor + duration,
                policy: policy,
                timingProvenance: provenance
            )
            if notes[noteIndex].graceSlash {
                entries[noteIndex].appendProvenance(.approximation(reason: "grace-slash-does-not-define-duration"))
            }
            cursor += duration
        }
    }

    func partition(durationTicks: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let total = max(count, durationTicks)
        let base = total / count
        let remainder = total % count
        return (0..<count).map { index in
            base + (index < remainder ? 1 : 0)
        }
    }

    func markApproximation(
        _ reason: String,
        noteIndices: [Int],
        entries: inout [MutableEntry]
    ) {
        for index in noteIndices {
            entries[index].appendProvenance(.approximation(reason: reason))
        }
    }
}
