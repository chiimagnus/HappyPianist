import Foundation

// ponytail: embedded in AVP; extract only when another Swift target needs it.

public struct ImprovStreamStartRequestV2: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var request: ImprovGenerateRequestV2

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case request
    }

    public init(protocolVersion: Int = 2, request: ImprovGenerateRequestV2) {
        type = "start"
        self.protocolVersion = protocolVersion
        self.request = request
    }
}

public struct ImprovStreamTimeRange: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = Self.sanitizeSeconds(start)
        self.end = max(Self.sanitizeSeconds(end), self.start)
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStart = Self.sanitizeSeconds(try container.decode(Double.self, forKey: .start))
        let decodedEnd = Self.sanitizeSeconds(try container.decode(Double.self, forKey: .end))
        start = decodedStart
        end = max(decodedEnd, decodedStart)
    }

    private static func sanitizeSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return max(0, seconds)
    }
}

public struct ImprovStreamChunkV2: Codable, Equatable, Sendable {
    public var type: String
    public var protocolVersion: Int
    public var seq: Int
    public var isFinal: Bool
    public var timeRange: ImprovStreamTimeRange
    public var events: [ImprovEvent]
    public var latencyMS: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol_version"
        case seq
        case isFinal = "is_final"
        case timeRange = "time_range"
        case events
        case latencyMS = "latency_ms"
    }

    public init(
        protocolVersion: Int = 2,
        seq: Int,
        isFinal: Bool,
        timeRange: ImprovStreamTimeRange,
        events: [ImprovEvent],
        latencyMS: Int? = nil
    ) {
        type = "chunk"
        self.protocolVersion = protocolVersion
        self.seq = seq
        self.isFinal = isFinal
        self.timeRange = timeRange
        self.events = events
        self.latencyMS = latencyMS
    }
}
