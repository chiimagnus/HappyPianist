import Foundation


public enum MusicXMLLogicalInstrumentClassification: String, Codable, Equatable, Hashable, Sendable {
    case piano
    case other
    case unknown
}

public enum MusicXMLLogicalInstrumentEvidenceKind: String, Codable, Equatable, Hashable, Sendable {
    case explicitPianoMetadata
    case splitKeyboardPartNames
    case complementarySingleStaffClefs
    case singlePlayablePart
    case unresolvedMetadata
}

public enum MusicXMLGrandStaffPartRole: String, Codable, Equatable, Hashable, Sendable {
    case upper
    case lower

    public var displayStaff: Int {
        self == .upper ? 1 : 2
    }
}

public struct MusicXMLGrandStaffPartAssignment: Codable, Equatable, Hashable, Sendable {
    public let partID: String
    public let role: MusicXMLGrandStaffPartRole
}

public struct MusicXMLLogicalInstrumentEvidence: Codable, Equatable, Hashable, Sendable {
    public let kind: MusicXMLLogicalInstrumentEvidenceKind
    public let partIDs: [String]
}

public struct MusicXMLLogicalInstrument: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let memberPartIDs: [String]
    public let classification: MusicXMLLogicalInstrumentClassification
    public let evidence: [MusicXMLLogicalInstrumentEvidence]
    public let grandStaffPartAssignments: [MusicXMLGrandStaffPartAssignment]

    public init(
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

public struct MusicXMLPartSelectionAmbiguity: Codable, Equatable, Sendable {
    public let candidateInstrumentIDs: [String]
    public let reason: String
}

public enum MusicXMLPracticePartSelection: Equatable, Sendable {
    case selected(MusicXMLLogicalInstrument)
    case ambiguous(MusicXMLPartSelectionAmbiguity)
    case unavailable
}
