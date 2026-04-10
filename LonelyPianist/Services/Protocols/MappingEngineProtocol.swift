import Foundation

struct ResolvedKeyStroke: Sendable {
    enum TriggerType: Sendable {
        case singleKey
        case chord
    }

    let triggerType: TriggerType
    let keyStroke: KeyStroke
    let sourceDescription: String
}

protocol MappingEngineProtocol: AnyObject {
    func reset()
    func process(event: MIDIEvent, payload: MappingConfigPayload) -> [ResolvedKeyStroke]
}
