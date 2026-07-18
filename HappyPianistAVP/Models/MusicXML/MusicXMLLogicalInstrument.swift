import Foundation

enum MusicXMLLogicalInstrumentClassification: String, Codable, Equatable, Hashable, Sendable {
    case piano
    case other
    case unknown
}

enum MusicXMLLogicalInstrumentEvidenceKind: String, Codable, Equatable, Hashable, Sendable {
    case explicitPianoMetadata
    case splitKeyboardPartNames
    case singlePlayablePart
    case unresolvedMetadata
}

struct MusicXMLLogicalInstrumentEvidence: Codable, Equatable, Hashable, Sendable {
    let kind: MusicXMLLogicalInstrumentEvidenceKind
    let partIDs: [String]
}

struct MusicXMLLogicalInstrument: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let memberPartIDs: [String]
    let classification: MusicXMLLogicalInstrumentClassification
    let evidence: [MusicXMLLogicalInstrumentEvidence]

    init(
        id: String,
        memberPartIDs: [String],
        classification: MusicXMLLogicalInstrumentClassification,
        evidence: [MusicXMLLogicalInstrumentEvidence]
    ) {
        self.id = id
        self.memberPartIDs = Array(Set(memberPartIDs)).sorted()
        self.classification = classification
        self.evidence = evidence
    }
}

struct MusicXMLPartSelectionAmbiguity: Codable, Equatable, Sendable {
    let candidateInstrumentIDs: [String]
    let reason: String
}

enum MusicXMLPracticePartSelection: Equatable, Sendable {
    case selected(MusicXMLLogicalInstrument)
    case ambiguous(MusicXMLPartSelectionAmbiguity)
    case unavailable
}
