import Foundation

public struct PerformanceSourceTimestamp: Codable, Equatable, Sendable {
    public let clockID: String
    public let seconds: TimeInterval

    public init(clockID: String, seconds: TimeInterval) {
        self.clockID = clockID
        self.seconds = seconds
    }
}
