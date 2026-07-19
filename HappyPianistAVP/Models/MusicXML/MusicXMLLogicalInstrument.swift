import Foundation

enum MusicXMLLogicalInstrumentClassification: String, Codable, Equatable, Hashable, Sendable {
    case piano
    case other
    case unknown
}

enum MusicXMLLogicalInstrumentEvidenceKind: String, Codable, Equatable, Hashable, Sendable {
    case explicitPianoMetadata
    case splitKeyboardPartNames
    case complementarySingleStaffClefs
    case singlePlayablePart
    case unresolvedMetadata
}

enum MusicXMLGrandStaffPartRole: String, Codable, Equatable, Hashable, Sendable {
    case upper
    case lower

    var displayStaff: Int { self == .upper ? 1 : 2 }
}

struct MusicXMLGrandStaffPartAssignment: Codable, Equatable, Hashable, Sendable {
    let partID: String
    let role: MusicXMLGrandStaffPartRole
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
    let grandStaffPartAssignments: [MusicXMLGrandStaffPartAssignment]

    init(
        id: String,
        memberPartIDs: [String],
        classification: MusicXMLLogicalInstrumentClassification,
        evidence: [MusicXMLLogicalInstrumentEvidence],
        grandStaffPartAssignments: [MusicXMLGrandStaffPartAssignment] = []
    ) {
        self.id = id
        self.memberPartIDs = Array(Set(memberPartIDs)).sorted()
        self.classification = classification
        self.evidence = evidence
        self.grandStaffPartAssignments = grandStaffPartAssignments.sorted { $0.partID < $1.partID }
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
