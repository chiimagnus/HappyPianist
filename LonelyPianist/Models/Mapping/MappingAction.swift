import Foundation

enum MappingActionType: String, Codable, CaseIterable, Sendable {
    case text
    case keyCombo
    case shortcut
}

struct MappingAction: Codable, Hashable, Sendable {
    var type: MappingActionType
    var value: String

    static func text(_ value: String) -> MappingAction {
        MappingAction(type: .text, value: value)
    }

    static func keyCombo(_ value: String) -> MappingAction {
        MappingAction(type: .keyCombo, value: value)
    }

    static func shortcut(_ value: String) -> MappingAction {
        MappingAction(type: .shortcut, value: value)
    }
}
