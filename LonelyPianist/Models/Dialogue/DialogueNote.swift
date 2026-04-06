import Foundation

struct DialogueNote: Codable, Equatable, Sendable {
    let note: Int
    let velocity: Int
    let time: TimeInterval
    let duration: TimeInterval
}

struct DialogueGenerateParams: Codable, Equatable, Sendable {
    var topP: Double = 0.95
    var maxTokens: Int = 256

    enum CodingKeys: String, CodingKey {
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}

