import Foundation

enum MusicXMLParserError: Error, Equatable {
    case invalidData
    case parseFailed
}

protocol MusicXMLParserProtocol {
    func parse(data: Data) throws -> MusicXMLScore
    func parse(fileURL: URL) throws -> MusicXMLScore
}

struct MusicXMLParser: MusicXMLParserProtocol {
    func parse(fileURL: URL) throws -> MusicXMLScore {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
    }

    func parse(data: Data) throws -> MusicXMLScore {
        let delegate = MusicXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MusicXMLParserError.parseFailed
        }
        return MusicXMLScore(notes: delegate.notes)
    }
}

private final class MusicXMLParserDelegate: NSObject, XMLParserDelegate {
    private let normalizedTicksPerQuarter = 480

    private(set) var notes: [MusicXMLNoteEvent] = []

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

    private var isInNote = false
    private var noteIsRest = false
    private var noteIsChord = false
    private var noteStep: String?
    private var noteAlter: Int?
    private var noteOctave: Int?
    private var noteDuration: Int?
    private var noteStaff: Int?
    private var noteVoice: Int?

    private var currentMeasureStartTick = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
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
        case "rest":
            if isInNote {
                noteIsRest = true
            }
        case "chord":
            if isInNote {
                noteIsChord = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        elementText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
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
        case "backup":
            isInBackup = false
        case "forward":
            isInForward = false
        case "measure":
            let endTick = partMeasureMaxTick[currentPartID] ?? currentMeasureStartTick
            partTick[currentPartID] = max(endTick, partTick[currentPartID] ?? 0)
        default:
            break
        }
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

        let midiNote: Int?
        if noteIsRest {
            midiNote = nil
        } else {
            midiNote = Self.makeMIDINote(step: noteStep, alter: noteAlter ?? 0, octave: noteOctave)
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

    private static func makeMIDINote(step: String?, alter: Int, octave: Int?) -> Int? {
        guard let step, let octave else { return nil }
        let stepBase: [String: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11
        ]
        guard let base = stepBase[step] else { return nil }
        return (octave + 1) * 12 + base + alter
    }
}
