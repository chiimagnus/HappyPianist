import MusicXML

public struct PracticeNotationScoreFacts: Equatable, Sendable {
    public let logicalInstrument: MusicXMLLogicalInstrument
    public let structuralPartID: String

    public init(logicalInstrument: MusicXMLLogicalInstrument, structuralPartID: String) {
        self.logicalInstrument = logicalInstrument
        self.structuralPartID = structuralPartID
    }

    public func sourceStaff(forDisplayedStaff staff: Int) -> (partID: String, staff: Int)? {
        guard staff == 1 || staff == 2 else { return nil }
        if let assignment = logicalInstrument.grandStaffPartAssignments.first(where: {
            $0.role.displayStaff == staff
        }) {
            return (assignment.partID, 1)
        }
        guard logicalInstrument.memberPartIDs.count == 1,
              let partID = logicalInstrument.memberPartIDs.first
        else { return nil }
        return (partID, staff)
    }
}
