import Foundation
@testable import LonelyPianistAVP
import Testing

@Test
func streamingChunkAssemblerDropsOverlappingTimeRanges() {
    var assembler = ImprovStreamingChunkAssembler()

    let first = ImprovStreamChunkV2(
        seq: 0,
        isFinal: false,
        timeRange: ImprovStreamTimeRange(start: 0.0, end: 1.0),
        events: [.note(note: 60, velocity: 90, time: 0.2, duration: 0.3)]
    )
    #expect(assembler.consume(first) != nil)
    #expect(assembler.lastSeq == 0)
    #expect(assembler.lastTimeRangeEnd == 1.0)

    let overlapping = ImprovStreamChunkV2(
        seq: 1,
        isFinal: false,
        timeRange: ImprovStreamTimeRange(start: 0.5, end: 1.5),
        events: [.note(note: 62, velocity: 90, time: 0.6, duration: 0.1)]
    )
    #expect(assembler.consume(overlapping) == nil)
    #expect(assembler.lastSeq == 0)
    #expect(assembler.lastTimeRangeEnd == 1.0)
}

@Test
func streamingChunkAssemblerDropsNonMonotonicSeq() {
    var assembler = ImprovStreamingChunkAssembler()

    let first = ImprovStreamChunkV2(
        seq: 1,
        isFinal: false,
        timeRange: ImprovStreamTimeRange(start: 0.0, end: 1.0),
        events: [.note(note: 60, velocity: 90, time: 0.2, duration: 0.3)]
    )
    #expect(assembler.consume(first) != nil)
    #expect(assembler.lastSeq == 1)

    let outOfOrder = ImprovStreamChunkV2(
        seq: 0,
        isFinal: false,
        timeRange: ImprovStreamTimeRange(start: 1.0, end: 2.0),
        events: [.note(note: 62, velocity: 90, time: 1.2, duration: 0.1)]
    )
    #expect(assembler.consume(outOfOrder) == nil)
    #expect(assembler.lastSeq == 1)
}

@Test
func streamingChunkAssemblerRebasesEventsByTimeRangeStart() async throws {
    var assembler = ImprovStreamingChunkAssembler()

    let c0 = ImprovStreamChunkV2(
        seq: 0,
        isFinal: false,
        timeRange: ImprovStreamTimeRange(start: 0.0, end: 1.0),
        events: [
            .cc(controller: 64, value: 127, time: 0.0),
            .note(note: 60, velocity: 90, time: 0.8, duration: 0.2),
        ]
    )
    let maybeE0 = assembler.consume(c0)
    let e0 = try #require(maybeE0)
    #expect(e0.first?.time == 0.0)

    let c1 = ImprovStreamChunkV2(
        seq: 1,
        isFinal: false,
        timeRange: ImprovStreamTimeRange(start: 1.0, end: 2.0),
        events: [
            .cc(controller: 64, value: 0, time: 1.0),
            .note(note: 62, velocity: 90, time: 1.2, duration: 0.2),
        ]
    )
    let maybeE1 = assembler.consume(c1)
    let e1 = try #require(maybeE1)
    #expect(e1.first?.time == 0.0)
    let note = try #require(e1.first(where: { $0.type == .note }))
    #expect(abs(note.time - 0.2) < 1e-9)

    let schedule0 = await Task.detached(priority: .userInitiated) {
        ImprovScheduleBuilder().buildSchedule(from: e0, leadInSeconds: 0)
    }.value
    let schedule1 = await Task.detached(priority: .userInitiated) {
        ImprovScheduleBuilder().buildSchedule(from: e1, leadInSeconds: 0)
    }.value

    #expect(schedule0.contains(where: { event in
        if case let .controlChange(controller, _) = event.kind { return controller == 64 }
        return false
    }))
    #expect(schedule1.contains(where: { event in
        if case let .controlChange(controller, _) = event.kind { return controller == 64 }
        return false
    }))
}

@Test
func streamingChunkTimeRangeDecodeSanitizesAndEnforcesNonDecreasingEnd() throws {
    let data = Data(
        """
        {
          "type": "chunk",
          "protocol_version": 2,
          "seq": 0,
          "is_final": false,
          "time_range": { "start": 1.0, "end": 0.5 },
          "events": []
        }
        """.utf8
    )

    let decoded = try JSONDecoder().decode(ImprovStreamChunkV2.self, from: data)
    #expect(decoded.timeRange.start == 1.0)
    #expect(decoded.timeRange.end == 1.0)

    let negative = Data(
        """
        {
          "type": "chunk",
          "protocol_version": 2,
          "seq": 0,
          "is_final": false,
          "time_range": { "start": -1.0, "end": -2.0 },
          "events": []
        }
        """.utf8
    )

    let decodedNegative = try JSONDecoder().decode(ImprovStreamChunkV2.self, from: negative)
    #expect(decodedNegative.timeRange.start == 0.0)
    #expect(decodedNegative.timeRange.end == 0.0)
}
