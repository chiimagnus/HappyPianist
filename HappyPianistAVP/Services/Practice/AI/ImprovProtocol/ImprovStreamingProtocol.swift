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
        self.start = start
        self.end = end
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStart = try container.decode(Double.self, forKey: .start)
        let decodedEnd = try container.decode(Double.self, forKey: .end)

        guard decodedStart.isFinite, decodedStart >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .start,
                in: container,
                debugDescription: "Stream time-range start must be finite and nonnegative."
            )
        }
        guard decodedEnd.isFinite, decodedEnd >= decodedStart else {
            throw DecodingError.dataCorruptedError(
                forKey: .end,
                in: container,
                debugDescription: "Stream time-range end must be finite and no earlier than start."
            )
        }

        start = decodedStart
        end = decodedEnd
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
