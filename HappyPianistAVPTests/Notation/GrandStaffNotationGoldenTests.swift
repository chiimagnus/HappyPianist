import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func notationFidelitySourceFactsMatchGolden() throws {
    try assertNotationGolden("source-facts", actual: sourceFactsSnapshot(try notationFidelityModel().projection))
}

@Test
func notationFidelityGlyphTokensMatchGolden() throws {
    try assertNotationGolden("glyph-tokens", actual: glyphTokenSnapshot(try notationFidelityModel().layout))
}

@Test
func notationFidelityGeometryMatchesGolden() throws {
    try assertNotationGolden("geometry", actual: geometrySnapshot(try notationFidelityModel().layout))
}

@Test
func notationFidelityLayoutMatchesGolden() throws {
    try assertNotationGolden("layout", actual: layoutSnapshot(try notationFidelityModel().layout))
}

private struct NotationFidelityModel {
    let projection: ScoreNotationProjection
    let layout: GrandStaffNotationLayout
}

private func notationFidelityModel() throws -> NotationFidelityModel {
    let fixture = try PianoPerformanceFixtureLoader().fixture(id: "notation-fidelity-piano")
    let score = try MusicXMLParser().parse(fileURL: fixture.url)
    let projection = ScoreNotationProjection(
        plan: makeTestScorePerformancePlan(from: score),
        sourceScore: score
    )
    let endTick = score.measures.map(\.endTick).max() ?? 0
    let layout = GrandStaffNotationLayoutService().makeLayout(
        projection: projection,
        measureSpans: score.measures,
        viewportWidthStaffSpaces: 240,
        scrollTick: Double(endTick) / 2
    )
    return NotationFidelityModel(projection: projection, layout: layout)
}

private func assertNotationGolden(_ name: String, actual: String) throws {
    let expected = try String(
        contentsOf: testFixtureURL("NotationFidelity/\(name).golden.txt"),
        encoding: .utf8
    )
    let terminatedActual = actual + "\n"
    #expect(terminatedActual == expected)
}

private func sourceFactsSnapshot(_ projection: ScoreNotationProjection) -> String {
    projection.sourceNotes.map { note in
        let pitch = note.writtenPitch.map {
            "\($0.step)\($0.octave):alter=\(fixed($0.alter)):acc=\($0.accidentalToken ?? "-")"
        } ?? "rest"
        let rhythm = note.writtenRhythm.map {
            let ratio = $0.timeModification.map {
                "\($0.actualNotes.map(String.init) ?? "-"):\($0.normalNotes.map(String.init) ?? "-")"
            } ?? "-"
            return "\($0.typeToken ?? "-"):dots=\($0.dotCount):ratio=\(ratio)"
        } ?? "-"
        let beams = note.beams.map {
            "\($0.numberToken ?? "1"):\(String(describing: $0.value))"
        }.joined(separator: ",")
        let ties = note.ties.map {
            "\($0.sourceElement.rawValue):\($0.typeToken ?? "-")"
        }.sorted().joined(separator: ",")
        let slurs = note.slurs.compactMap(\.typeToken).sorted().joined(separator: ",")
        let tuplets = note.tuplets.compactMap(\.typeToken).sorted().joined(separator: ",")
        let articulations = note.articulations.map(\.rawValue).sorted().joined(separator: ",")
        let fingers = note.fingerings.map(\.text).joined(separator: ",")
        return [
            note.id.description,
            "tick=\(note.writtenOnTick)",
            "duration=\(note.writtenDurationTicks)",
            "staff=\(note.staff)",
            "voice=\(note.voice)",
            "pitch=\(pitch)",
            "rhythm=\(rhythm)",
            "stem=\(String(describing: note.stem))",
            "beams=\(beams.isEmpty ? "-" : beams)",
            "ties=\(ties.isEmpty ? "-" : ties)",
            "slurs=\(slurs.isEmpty ? "-" : slurs)",
            "tuplets=\(tuplets.isEmpty ? "-" : tuplets)",
            "articulations=\(articulations.isEmpty ? "-" : articulations)",
            "arpeggio=\(note.arpeggiate?.direction?.rawValue ?? "-")",
            "fingers=\(fingers.isEmpty ? "-" : fingers)",
        ].joined(separator: "|")
    }.joined(separator: "\n")
}

private func glyphTokenSnapshot(_ layout: GrandStaffNotationLayout) -> String {
    let chordsByID = Dictionary(uniqueKeysWithValues: layout.chords.map { ($0.id, $0) })
    let items = layout.items.sorted(by: notationItemOrder).map { item in
        let chord = item.chordID.flatMap { chordsByID[$0] }
        let flag = item.beamID == nil
            ? chord?.noteValue.flagGlyphToken(stemDirection: chord?.stem.direction ?? .up)
            : nil
        return [
            "note@\(item.tick):s\(item.staffNumber):v\(item.voice)",
            "head=\(item.noteheadGlyphToken?.rawValue ?? "-")",
            "acc=\(item.displayedAccidental?.glyphToken?.rawValue ?? "-")",
            "flag=\(flag?.rawValue ?? "-")",
            "dots=\(item.dotCount > 0 ? GrandStaffGlyphToken.augmentationDot.rawValue : "-")",
            "art=\(item.articulationGlyphTokens.map(\.rawValue).joined(separator: ","))",
        ].joined(separator: "|")
    }
    let rests = layout.rests.sorted(by: restOrder).map {
        "rest@\($0.tick):s\($0.staffNumber):v\($0.voice)|glyph=\($0.glyphToken?.rawValue ?? "-")|dots=\($0.dotCount)"
    }
    let marks = layout.marks.sorted(by: markOrder).map {
        "mark@\($0.tick):s\($0.staffNumber):\(markKind($0.kind))|glyph=\($0.glyphToken?.rawValue ?? "-")|text=\($0.text ?? "-")"
    }
    let attributes = layout.attributeChanges.sorted(by: attributeOrder).map {
        "attribute@\($0.tick):s\($0.staffNumber)|clef=\($0.clefGlyphToken?.rawValue ?? "-")|key=\($0.keySignatureFifths.map(String.init) ?? "-")|time=\($0.timeSignatureText ?? "-")"
    }
    return (items + rests + marks + attributes).joined(separator: "\n")
}

private func geometrySnapshot(_ layout: GrandStaffNotationLayout) -> String {
    let items = layout.items.sorted(by: notationItemOrder).map {
        [
            "item@\($0.tick):s\($0.staffNumber):v\($0.voice):step=\($0.staffStep)",
            "x=\(fixed($0.xPosition))",
            "headX=\(fixed($0.noteheadXOffset))",
            "accX=\(fixed($0.accidentalXOffsetStaffSpaces))",
            "dotX=\(fixed($0.dotXOffsetStaffSpaces))",
            "dotStep=\($0.dotStaffStep.map(String.init) ?? "-")",
        ].joined(separator: "|")
    }
    let chords = layout.chords.sorted { $0.tick == $1.tick ? $0.id < $1.id : $0.tick < $1.tick }.map {
        "chord@\($0.tick)|x=\(fixed($0.xPosition))|stem=\(String(describing: $0.stem.direction)):visible=\($0.stem.isVisible):x=\(fixed($0.stem.xOffset))"
    }
    let beams = layout.beams.sorted { $0.id < $1.id }.flatMap { beam in
        beam.segments.map {
            "beam|level=\($0.level)|start=\($0.startChordID)|end=\($0.endChordID)|hook=\($0.hookDirection.map { String(describing: $0) } ?? "-")"
        }
    }
    let ledgers = layout.ledgerLines.sorted {
        if $0.tick != $1.tick { return $0.tick < $1.tick }
        if $0.staffNumber != $1.staffNumber { return $0.staffNumber < $1.staffNumber }
        return $0.staffStep < $1.staffStep
    }.map {
        "ledger@\($0.tick):s\($0.staffNumber):step=\($0.staffStep)|x=\(fixed($0.xPosition))|min=\(fixed($0.minXOffsetStaffSpaces))|max=\(fixed($0.maxXOffsetStaffSpaces))"
    }
    let spanners = layout.ties.map {
        "tie|x=\(fixed($0.startXPosition))...\(fixed($0.endXPosition))|continuation=\($0.continuesFromPrevious),\($0.continuesToNext)"
    } + layout.slurs.map {
        "slur|x=\(fixed($0.startXPosition))...\(fixed($0.endXPosition))|continuation=\($0.continuesFromPrevious),\($0.continuesToNext)"
    } + layout.tuplets.map {
        "tuplet|x=\(fixed($0.startXPosition))...\(fixed($0.endXPosition))|level=\($0.nestingLevel)|display=\($0.displayNumber.map(String.init) ?? "-")"
    }
    let marks = layout.marks.sorted(by: markOrder).map {
        "mark@\($0.tick):s\($0.staffNumber):\(markKind($0.kind))|x=\(fixed($0.xPosition))|placement=\(String(describing: $0.placement))|collision=\($0.collisionLevel)|steps=\($0.minimumStaffStep.map(String.init) ?? "-"),\($0.maximumStaffStep.map(String.init) ?? "-")"
    }
    return (items + chords + beams + ledgers + spanners + marks).joined(separator: "\n")
}

private func layoutSnapshot(_ layout: GrandStaffNotationLayout) -> String {
    let counts = [
        "items=\(layout.items.count)", "chords=\(layout.chords.count)", "rests=\(layout.rests.count)",
        "ties=\(layout.ties.count)", "slurs=\(layout.slurs.count)", "tuplets=\(layout.tuplets.count)",
        "barlines=\(layout.barlines.count)", "beams=\(layout.beams.count)", "ledgers=\(layout.ledgerLines.count)",
        "marks=\(layout.marks.count)", "attributes=\(layout.attributeChanges.count)",
    ].joined(separator: "|")
    let notes = layout.items.sorted(by: notationItemOrder).map {
        "note@\($0.tick):s\($0.staffNumber):v\($0.voice):hand=\(String(describing: $0.hand)):beam=\($0.beamID == nil ? "no" : "yes")"
    }
    let rests = layout.rests.sorted(by: restOrder).map {
        "rest@\($0.tick):s\($0.staffNumber):v\($0.voice):\(noteValue($0.noteValue))"
    }
    let barlines = layout.barlines.sorted { $0.tick < $1.tick }.map { "barline@\($0.tick)" }
    let attributes = layout.attributeChanges.sorted(by: attributeOrder).map {
        "attribute@\($0.tick):s\($0.staffNumber):clef=\($0.clefSignToken ?? "-"):key=\($0.keySignatureFifths.map(String.init) ?? "-"):time=\($0.timeSignatureText ?? "-")"
    }
    return ([counts] + notes + rests + barlines + attributes).joined(separator: "\n")
}

private func notationItemOrder(_ lhs: GrandStaffNotationItem, _ rhs: GrandStaffNotationItem) -> Bool {
    if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
    if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
    if lhs.voice != rhs.voice { return lhs.voice < rhs.voice }
    if lhs.staffStep != rhs.staffStep { return lhs.staffStep < rhs.staffStep }
    return lhs.id < rhs.id
}

private func restOrder(_ lhs: GrandStaffNotationRest, _ rhs: GrandStaffNotationRest) -> Bool {
    if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
    if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
    return lhs.voice < rhs.voice
}

private func markOrder(_ lhs: GrandStaffNotationMark, _ rhs: GrandStaffNotationMark) -> Bool {
    if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
    if lhs.staffNumber != rhs.staffNumber { return lhs.staffNumber < rhs.staffNumber }
    return lhs.id < rhs.id
}

private func attributeOrder(
    _ lhs: GrandStaffNotationAttributeChange,
    _ rhs: GrandStaffNotationAttributeChange
) -> Bool {
    lhs.tick == rhs.tick ? lhs.staffNumber < rhs.staffNumber : lhs.tick < rhs.tick
}

private func markKind(_ kind: GrandStaffNotationMark.Kind) -> String {
    switch kind {
    case .dynamic: "dynamic"
    case .tempo: "tempo"
    case .text: "text"
    case .pedalStart: "pedalStart"
    case .pedalStop: "pedalStop"
    case .pedalChange: "pedalChange"
    case .pedalContinue: "pedalContinue"
    case .fermata: "fermata"
    case .repeatForward: "repeatForward"
    case .repeatBackward: "repeatBackward"
    case .endingStart: "endingStart"
    case .endingStop: "endingStop"
    case .endingDiscontinue: "endingDiscontinue"
    case let .articulation(token): "articulation:\(token.rawValue)"
    case let .arpeggio(token): "arpeggio:\(token.rawValue)"
    case .fingering: "fingering"
    }
}

private func noteValue(_ value: GrandStaffNoteValue) -> String {
    switch value {
    case .whole: "whole"
    case .half: "half"
    case .quarter: "quarter"
    case .eighth: "eighth"
    case .sixteenth: "16th"
    case .thirtySecond: "32nd"
    case .sixtyFourth: "64th"
    case .oneHundredTwentyEighth: "128th"
    case let .unsupported(token): "unsupported:\(token ?? "-")"
    }
}

private func fixed(_ value: Double) -> String {
    value.formatted(
        .number
            .locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never)
            .precision(.fractionLength(3))
    )
}

private func fixed(_ value: Double?) -> String {
    value.map(fixed) ?? "-"
}
