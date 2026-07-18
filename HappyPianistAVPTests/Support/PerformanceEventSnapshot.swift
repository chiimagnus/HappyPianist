import Foundation
@testable import HappyPianistAVP

struct PerformanceEventSnapshot {
    private let encoder = PianoPerformanceSnapshotEncoder()

    func encode(_ timeline: AutoplayPerformanceTimeline) -> String {
        encoder.encode(lines: timeline.events.enumerated().map { position, event in
            encoder.encode(fields: [
                ("position", String(position)),
                ("eventID", String(event.id)),
                ("sourceEventID", event.sourceEventID ?? "unresolved"),
                ("tick", String(event.tick)),
                ("kind", timelineKind(event.kind)),
            ])
        })
    }

    func encode(_ events: [PracticeSequencerMIDIEvent]) -> String {
        encoder.encode(lines: events.enumerated().map { position, event in
            encoder.encode(fields: [
                ("position", String(position)),
                ("sourceEventID", event.sourceEventID ?? "unresolved"),
                ("seconds", encoder.encode(event.timeSeconds)),
                ("kind", sequencerKind(event.kind)),
            ])
        })
    }

    private func timelineKind(_ kind: AutoplayPerformanceTimeline.EventKind) -> String {
        switch kind {
        case let .pauseSeconds(seconds):
            "pause:\(encoder.encode(seconds))"
        case let .noteOff(midi):
            "noteOff:\(midi)"
        case let .controlChange(controller, value):
            "cc:\(controller):\(value)"
        case let .tempo(quarterBPM, endTick, endQuarterBPM):
            "tempo:\(encoder.encode(quarterBPM)):\(endTick.map(String.init) ?? "nil"):\(endQuarterBPM.map(encoder.encode) ?? "nil")"
        case let .noteOn(midi, velocity):
            "noteOn:\(midi):\(velocity)"
        case let .advanceStep(index):
            "advanceStep:\(index)"
        case let .advanceGuide(index, guideID):
            "advanceGuide:\(index):\(guideID)"
        }
    }

    private func sequencerKind(_ kind: PracticeSequencerMIDIEvent.Kind) -> String {
        switch kind {
        case let .noteOn(midi, velocity):
            "noteOn:\(midi):\(velocity)"
        case let .noteOff(midi):
            "noteOff:\(midi)"
        case let .controlChange(controller, value):
            "cc:\(controller):\(value)"
        case let .pitchBend(value):
            "pitchBend:\(value)"
        case let .programChange(program):
            "program:\(program)"
        case let .channelPressure(value):
            "channelPressure:\(value)"
        case let .polyPressure(midi, value):
            "polyPressure:\(midi):\(value)"
        }
    }
}
