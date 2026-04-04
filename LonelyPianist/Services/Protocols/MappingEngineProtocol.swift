import Foundation

struct ResolvedMappingAction: Sendable {
    enum TriggerType: Sendable {
        case singleKey
        case chord
        case melody
    }

    let triggerType: TriggerType
    let action: MappingAction
    let sourceDescription: String
}

protocol MappingEngineProtocol: AnyObject {
    func reset()
    func process(event: MIDIEvent, profile: MappingProfile) -> [ResolvedMappingAction]
}
