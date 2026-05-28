import Foundation
import ImprovProtocol

struct ImprovStreamingChunkAssembler: Sendable {
    private(set) var lastSeq: Int = -1
    private(set) var lastTimeRangeEnd: Double = 0

    mutating func consume(_ chunk: ImprovStreamChunkV2) -> [ImprovEvent]? {
        if chunk.seq <= lastSeq { return nil }
        if chunk.timeRange.start + 1e-9 < lastTimeRangeEnd { return nil }

        lastSeq = chunk.seq
        lastTimeRangeEnd = max(lastTimeRangeEnd, chunk.timeRange.end)

        return chunk.events.map { event in
            var rebased = event
            rebased.time = max(0, rebased.time - chunk.timeRange.start)
            return rebased
        }
    }
}

