import Foundation

final class MusicXMLParserDelegate: NSObject, XMLParserDelegate {
    private let normalizedTicksPerQuarter = 480

    private(set) var notes: [MusicXMLNoteEvent] = []
    private(set) var tempoEvents: [MusicXMLTempoEvent] = []
    private(set) var soundDirectives: [MusicXMLSoundDirective] = []
    private(set) var pedalEvents: [MusicXMLPedalEvent] = []
    private(set) var measures: [MusicXMLMeasureSpan] = []
    private(set) var repeatDirectives: [MusicXMLRepeatDirective] = []
    private(set) var endingDirectives: [MusicXMLEndingDirective] = []

    private enum TempoSource: Int {
        case metronome = 0
        case sound = 1
    }

    private struct RawTempoEvent {
        let partID: String
        let tick: Int
        let quarterBPM: Double
        let source: TempoSource
    }

    private var currentPartID = "P1"
    private var currentMeasureNumber = 1

    private var partDivisions: [String: Int] = [:]
    private var partTick: [String: Int] = [:]
    private var partMeasureMaxTick: [String: Int] = [:]
    private var partLastNonChordStartTick: [String: Int] = [:]

    private var currentElement = ""
    private var elementText = ""

    private var isInAttributes = false
    private var isInBackup = false
    private var isInForward = false
    private var isInDirection = false
    private var isInBarline = false

    private var isInNote = false
    private var noteIsRest = false
    private var noteIsChord = false
    private var noteStep: String?
    private var noteAlter: Int?
    private var noteOctave: Int?
    private var noteDuration: Int?
    private var noteStaff: Int?
    private var noteVoice: Int?
    private var noteTieStart = false
    private var noteTieStop = false

    private var isInDirectionTypeMetronome = false
    private var metronomeBeatUnit: String?
    private var metronomeHasDot = false
    private var metronomePerMinute: Double?

    private var rawTempoEventsByPart: [String: [RawTempoEvent]] = [:]

    private var currentMeasureStartTick = 0
    private var currentDirectionOffsetTicks = 0
    private var currentDirectionMeasureStartTick = 0
    private var currentDirectionTempoStartIndex = 0
    private var currentDirectionSoundStartIndex = 0
    private var currentDirectionPedalStartIndex = 0

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        elementText = ""

        switch elementName {
            case "part":
                currentPartID = attributeDict["id"] ?? "P1"
                if partDivisions[currentPartID] == nil {
                    partDivisions[currentPartID] = 1
                }
                currentMeasureStartTick = partTick[currentPartID] ?? 0
                partMeasureMaxTick[currentPartID] = currentMeasureStartTick
            case "measure":
                currentMeasureNumber = Int(attributeDict["number"] ?? "") ?? (currentMeasureNumber + 1)
                currentMeasureStartTick = partTick[currentPartID] ?? 0
                partMeasureMaxTick[currentPartID] = currentMeasureStartTick
                partLastNonChordStartTick[currentPartID] = nil
            case "attributes":
                isInAttributes = true
            case "direction":
                isInDirection = true
                currentDirectionOffsetTicks = 0
                currentDirectionMeasureStartTick = currentMeasureStartTick
                currentDirectionTempoStartIndex = rawTempoEventsByPart[currentPartID]?.count ?? 0
                currentDirectionSoundStartIndex = soundDirectives.count
                currentDirectionPedalStartIndex = pedalEvents.count
            case "direction-type":
                break
            case "pedal":
                recordPedalEvent(attributes: attributeDict)
            case "barline":
                isInBarline = true
            case "repeat":
                if isInBarline, let rawDirection = attributeDict["direction"], let direction = MusicXMLRepeatDirection(rawValue: rawDirection) {
                    repeatDirectives.append(
                        MusicXMLRepeatDirective(
                            partID: currentPartID,
                            measureNumber: currentMeasureNumber,
                            direction: direction
                        )
                    )
                }
            case "ending":
                if isInBarline,
                   let number = attributeDict["number"],
                   let rawType = attributeDict["type"],
                   let type = MusicXMLEndingType(rawValue: rawType)
                {
                    endingDirectives.append(
                        MusicXMLEndingDirective(
                            partID: currentPartID,
                            measureNumber: currentMeasureNumber,
                            number: number,
                            type: type
                        )
                    )
                }
            case "metronome":
                if isInDirection {
                    isInDirectionTypeMetronome = true
                    metronomeBeatUnit = nil
                    metronomeHasDot = false
                    metronomePerMinute = nil
                }
            case "sound":
                if isInDirection, let tempoText = attributeDict["tempo"], let bpm = Double(tempoText) {
                    recordTempoEvent(quarterBPM: bpm, source: .sound)
                }
                if isInDirection {
                    recordSoundDirective(attributes: attributeDict)
                }
            case "backup":
                isInBackup = true
            case "forward":
                isInForward = true
            case "note":
                isInNote = true
                noteIsRest = false
                noteIsChord = false
                noteStep = nil
                noteAlter = nil
                noteOctave = nil
                noteDuration = nil
                noteStaff = nil
                noteVoice = nil
                noteTieStart = false
                noteTieStop = false
            case "rest":
                if isInNote {
                    noteIsRest = true
                }
            case "chord":
                if isInNote {
                    noteIsChord = true
                }
            case "tie", "tied":
                if isInNote {
                    let type = attributeDict["type"]?.lowercased()
                    if type == "start" {
                        noteTieStart = true
                    } else if type == "stop" {
                        noteTieStop = true
                    }
                }
            default:
                break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        elementText += string
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        let text = elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            currentElement = ""
            elementText = ""
        }

        switch elementName {
            case "divisions" where isInAttributes:
                if let value = Int(text), value > 0 {
                    partDivisions[currentPartID] = value
                }
            case "beat-unit" where isInDirectionTypeMetronome:
                metronomeBeatUnit = text
            case "beat-unit-dot" where isInDirectionTypeMetronome:
                metronomeHasDot = true
            case "per-minute" where isInDirectionTypeMetronome:
                metronomePerMinute = Double(text)
            case "metronome":
                finalizeMetronomeTempoIfNeeded()
                isInDirectionTypeMetronome = false
            case "offset" where isInDirection:
                if let rawOffset = Int(text) {
                    applyDirectionOffset(rawOffset)
                }
            case "duration":
                if let duration = Int(text), duration >= 0 {
                    let normalizedDuration = normalizeDuration(duration)
                    if isInNote {
                        noteDuration = normalizedDuration
                    } else if isInBackup {
                        moveCurrentTick(by: -normalizedDuration)
                    } else if isInForward {
                        moveCurrentTick(by: normalizedDuration)
                    }
                }
            case "step" where isInNote:
                noteStep = text
            case "alter" where isInNote:
                noteAlter = Int(text)
            case "octave" where isInNote:
                noteOctave = Int(text)
            case "staff" where isInNote:
                noteStaff = Int(text)
            case "voice" where isInNote:
                noteVoice = Int(text)
            case "note":
                finalizeNote()
                isInNote = false
            case "attributes":
                isInAttributes = false
            case "direction":
                isInDirection = false
                currentDirectionOffsetTicks = 0
                currentDirectionMeasureStartTick = 0
                currentDirectionTempoStartIndex = 0
                currentDirectionSoundStartIndex = 0
                currentDirectionPedalStartIndex = 0
            case "barline":
                isInBarline = false
            case "backup":
                isInBackup = false
            case "forward":
                isInForward = false
            case "measure":
                let endTick = partMeasureMaxTick[currentPartID] ?? currentMeasureStartTick
                measures.append(
                    MusicXMLMeasureSpan(
                        partID: currentPartID,
                        measureNumber: currentMeasureNumber,
                        startTick: currentMeasureStartTick,
                        endTick: endTick
                    )
                )
                partTick[currentPartID] = max(endTick, partTick[currentPartID] ?? 0)
            default:
                break
        }
    }

    private func recordPedalEvent(attributes: [String: String]) {
        guard isInDirection else { return }

        guard let rawType = attributes["type"]?.lowercased() else { return }

        let tick = currentDirectionEventTick()
        let base = (
            partID: currentPartID,
            measureNumber: currentMeasureNumber,
            tick: tick
        )

        switch rawType {
            case "start":
                pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .start,
                        isDown: true
                    )
                )
            case "stop":
                pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .stop,
                        isDown: false
                    )
                )
            case "change":
                pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .change,
                        isDown: false
                    )
                )
                pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .change,
                        isDown: true
                    )
                )
            case "continue":
                pedalEvents.append(
                    MusicXMLPedalEvent(
                        partID: base.partID,
                        measureNumber: base.measureNumber,
                        tick: base.tick,
                        kind: .continue,
                        isDown: nil
                    )
                )
            default:
                #if DEBUG
                print("MusicXMLParser: ignored pedal type '\(rawType)' at \(base.partID) measure \(base.measureNumber) tick \(base.tick)")
                #endif
        }
    }

    func parserDidEndDocument(_: XMLParser) {
        tempoEvents = finalizeTempoEvents()
    }

    private func finalizeNote() {
        guard let duration = noteDuration else { return }

        let currentTick = partTick[currentPartID] ?? currentMeasureStartTick
        let startTick: Int
        if noteIsChord {
            startTick = partLastNonChordStartTick[currentPartID] ?? currentTick
        } else {
            startTick = currentTick
            partLastNonChordStartTick[currentPartID] = startTick
            partTick[currentPartID] = currentTick + duration
        }

        let midiNote: Int? = if noteIsRest {
            nil
        } else {
            Self.makeMIDINote(step: noteStep, alter: noteAlter ?? 0, octave: noteOctave)
        }

        notes.append(
            MusicXMLNoteEvent(
                partID: currentPartID,
                measureNumber: currentMeasureNumber,
                tick: startTick,
                durationTicks: duration,
                midiNote: midiNote,
                isRest: noteIsRest,
                isChord: noteIsChord,
                tieStart: noteTieStart,
                tieStop: noteTieStop,
                staff: noteStaff,
                voice: noteVoice
            )
        )

        let noteEndTick = startTick + duration
        let currentMax = partMeasureMaxTick[currentPartID] ?? currentMeasureStartTick
        partMeasureMaxTick[currentPartID] = max(currentMax, noteEndTick, partTick[currentPartID] ?? currentTick)
    }

    private func moveCurrentTick(by delta: Int) {
        let current = partTick[currentPartID] ?? currentMeasureStartTick
        let moved = max(currentMeasureStartTick, current + delta)
        partTick[currentPartID] = moved
        let currentMax = partMeasureMaxTick[currentPartID] ?? currentMeasureStartTick
        partMeasureMaxTick[currentPartID] = max(currentMax, moved)
    }

    private func normalizeDuration(_ rawDuration: Int) -> Int {
        let divisions = max(1, partDivisions[currentPartID] ?? 1)
        let normalized = Double(rawDuration) * Double(normalizedTicksPerQuarter) / Double(divisions)
        return max(0, Int(normalized.rounded()))
    }

    private func normalizeSignedDuration(_ rawDuration: Int) -> Int {
        if rawDuration == 0 {
            return 0
        }
        let sign = rawDuration >= 0 ? 1 : -1
        let normalized = normalizeDuration(abs(rawDuration))
        return sign * normalized
    }

    private func applyDirectionOffset(_ rawOffset: Int) {
        let newOffset = normalizeSignedDuration(rawOffset)
        let delta = newOffset - currentDirectionOffsetTicks
        guard delta != 0 else { return }

        if var tempoEvents = rawTempoEventsByPart[currentPartID], currentDirectionTempoStartIndex < tempoEvents.count {
            for i in currentDirectionTempoStartIndex ..< tempoEvents.count {
                let shifted = max(currentDirectionMeasureStartTick, tempoEvents[i].tick + delta)
                tempoEvents[i] = RawTempoEvent(
                    partID: tempoEvents[i].partID,
                    tick: shifted,
                    quarterBPM: tempoEvents[i].quarterBPM,
                    source: tempoEvents[i].source
                )
            }
            rawTempoEventsByPart[currentPartID] = tempoEvents
        }

        if currentDirectionSoundStartIndex < soundDirectives.count {
            for i in currentDirectionSoundStartIndex ..< soundDirectives.count {
                let shifted = max(currentDirectionMeasureStartTick, soundDirectives[i].tick + delta)
                soundDirectives[i] = MusicXMLSoundDirective(
                    partID: soundDirectives[i].partID,
                    measureNumber: soundDirectives[i].measureNumber,
                    tick: shifted,
                    segno: soundDirectives[i].segno,
                    coda: soundDirectives[i].coda,
                    tocoda: soundDirectives[i].tocoda,
                    dalsegno: soundDirectives[i].dalsegno,
                    dacapo: soundDirectives[i].dacapo
                )
            }
        }

        if currentDirectionPedalStartIndex < pedalEvents.count {
            for i in currentDirectionPedalStartIndex ..< pedalEvents.count {
                let shifted = max(currentDirectionMeasureStartTick, pedalEvents[i].tick + delta)
                pedalEvents[i] = MusicXMLPedalEvent(
                    partID: pedalEvents[i].partID,
                    measureNumber: pedalEvents[i].measureNumber,
                    tick: shifted,
                    kind: pedalEvents[i].kind,
                    isDown: pedalEvents[i].isDown
                )
            }
        }

        currentDirectionOffsetTicks = newOffset
    }

    private func currentDirectionEventTick() -> Int {
        let baseTick = partTick[currentPartID] ?? currentMeasureStartTick
        guard isInDirection else { return baseTick }
        let shifted = baseTick + currentDirectionOffsetTicks
        return max(currentDirectionMeasureStartTick, shifted)
    }

    private func recordTempoEvent(quarterBPM: Double, source: TempoSource) {
        guard quarterBPM.isFinite, quarterBPM > 0 else { return }

        let tick = currentDirectionEventTick()
        let event = RawTempoEvent(partID: currentPartID, tick: tick, quarterBPM: quarterBPM, source: source)
        rawTempoEventsByPart[currentPartID, default: []].append(event)
    }

    private func recordSoundDirective(attributes: [String: String]) {
        let segno = attributes["segno"].flatMap { $0.isEmpty ? nil : $0 }
        let coda = attributes["coda"].flatMap { $0.isEmpty ? nil : $0 }
        let tocoda = attributes["tocoda"].flatMap { $0.isEmpty ? nil : $0 }
        let dalsegno = attributes["dalsegno"].flatMap { $0.isEmpty ? nil : $0 }
        let dacapo = attributes["dacapo"].flatMap { $0.isEmpty ? nil : $0 }

        guard segno != nil || coda != nil || tocoda != nil || dalsegno != nil || dacapo != nil else {
            return
        }

        let tick = currentDirectionEventTick()
        soundDirectives.append(
            MusicXMLSoundDirective(
                partID: currentPartID,
                measureNumber: currentMeasureNumber,
                tick: tick,
                segno: segno,
                coda: coda,
                tocoda: tocoda,
                dalsegno: dalsegno,
                dacapo: dacapo
            )
        )
    }

    private func finalizeMetronomeTempoIfNeeded() {
        guard let beatUnit = metronomeBeatUnit?.lowercased(),
              let perMinute = metronomePerMinute,
              perMinute.isFinite,
              perMinute > 0
        else {
            return
        }

        guard beatUnit == "quarter", metronomeHasDot == false else {
            #if DEBUG
            print("MusicXMLParser: ignoring metronome beatUnit=\(beatUnit) dot=\(metronomeHasDot)")
            #endif
            return
        }

        recordTempoEvent(quarterBPM: perMinute, source: .metronome)
    }

    private func finalizeTempoEvents() -> [MusicXMLTempoEvent] {
        let primaryPart = "P1"
        let rawEvents: [RawTempoEvent]
        if let p1Events = rawTempoEventsByPart[primaryPart], p1Events.isEmpty == false {
            rawEvents = p1Events
        } else {
            rawEvents = rawTempoEventsByPart.keys.sorted().flatMap { partID in
                rawTempoEventsByPart[partID] ?? []
            }
        }

        guard rawEvents.isEmpty == false else { return [] }

        var byTick: [Int: RawTempoEvent] = [:]
        for event in rawEvents {
            if let existing = byTick[event.tick] {
                if event.source.rawValue > existing.source.rawValue {
                    byTick[event.tick] = event
                } else if event.source == existing.source {
                    byTick[event.tick] = event
                }
            } else {
                byTick[event.tick] = event
            }
        }

        return byTick.values
            .sorted { $0.tick < $1.tick }
            .map { MusicXMLTempoEvent(tick: $0.tick, quarterBPM: $0.quarterBPM) }
    }

    private static func makeMIDINote(step: String?, alter: Int, octave: Int?) -> Int? {
        guard let step, let octave else { return nil }
        let stepBase: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]
        guard let base = stepBase[step] else { return nil }
        return (octave + 1) * 12 + base + alter
    }
}
