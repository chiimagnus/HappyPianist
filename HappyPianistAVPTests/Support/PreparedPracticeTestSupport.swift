@testable import HappyPianistAVP

func makeTestPreparedPracticeScoreContext(
    sourceScore: MusicXMLScore? = nil,
    preparedScore: MusicXMLScore? = nil,
    handAssignments: [MusicXMLSourceNoteID: ScoreHandAssignment] = [:]
) -> PreparedPracticeScoreContext {
    let instrument = MusicXMLLogicalInstrument(
        id: "piano:P1",
        memberPartIDs: ["P1"],
        classification: .piano,
        evidence: [
            MusicXMLLogicalInstrumentEvidence(
                kind: .explicitPianoMetadata,
                partIDs: ["P1"]
            ),
        ]
    )
    let fallbackScore = MusicXMLScore(
        partMetadata: [MusicXMLPartMetadata(partID: "P1", name: "Piano")],
        logicalInstruments: [instrument],
        notes: []
    )
    let sourceScore = sourceScore ?? fallbackScore
    return PreparedPracticeScoreContext(
        sourceScore: sourceScore,
        preparedScore: preparedScore ?? sourceScore,
        logicalInstrument: instrument,
        structuralPartID: "P1",
        orderSelection: MusicXMLOrderSelection(requested: .written, applied: .written),
        handAssignments: handAssignments
    )
}
