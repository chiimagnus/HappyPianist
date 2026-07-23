struct MIDIPerformanceObservationAdapter {
    private var synchronizer: PerformanceClockSynchronizer
    private let estimatedLatencySeconds: Double?

    init(
        synchronizer: PerformanceClockSynchronizer = PerformanceClockSynchronizer(),
        estimatedLatencySeconds: Double? = nil
    ) {
        self.synchronizer = synchronizer
        self.estimatedLatencySeconds = estimatedLatencySeconds
    }

    mutating func observation(
        for event: MIDI1InputEvent,
        generation: UInt64
    ) -> PerformanceObservation {
        PerformanceObservation(
            id: event.observationID,
            source: source(kind: .midi1, midiSource: event.source, generation: generation),
            timing: timing(source: event.sourceTimestamp, hostSeconds: event.receivedAtUptimeSeconds),
            event: observationEvent(event.kind),
            channel: event.channel,
            group: event.group
        )
    }

    mutating func observation(
        for event: MIDI2InputEvent,
        generation: UInt64
    ) -> PerformanceObservation {
        PerformanceObservation(
            id: event.observationID,
            source: source(kind: .midi2, midiSource: event.source, generation: generation),
            timing: timing(source: event.sourceTimestamp, hostSeconds: event.receivedAtUptimeSeconds),
            event: observationEvent(event.kind),
            channel: event.channel,
            group: event.group
        )
    }

    mutating func resetClockCalibration() {
        synchronizer.reset()
    }

    private mutating func timing(
        source: PerformanceSourceTimestamp?,
        hostSeconds: Double
    ) -> PerformanceClockReading {
        synchronizer.reading(
            source: source,
            receivedAt: PerformanceMonotonicInstant(seconds: hostSeconds),
            estimatedLatencySeconds: estimatedLatencySeconds
        )
    }

    private func source(
        kind: PerformanceObservation.Source.Kind,
        midiSource: MIDIInputSource,
        generation: UInt64
    ) -> PerformanceObservation.Source {
        let id = switch midiSource.identifier {
        case let .endpointUniqueID(value):
            "endpoint:\(value)"
        case let .sourceIndex(value):
            "source-index:\(value)"
        }
        return PerformanceObservation.Source(kind: kind, id: id, generation: generation)
    }

    private func observationEvent(_ event: MIDI1InputEvent.Kind) -> PerformanceObservation.Event {
        switch event {
        case let .noteOn(note, velocity) where velocity == 0:
            .noteOff(note: note, releaseVelocity: .init(midi1: 0))
        case let .noteOn(note, velocity):
            .noteOn(note: note, velocity: .init(midi1: velocity))
        case let .noteOff(note, velocity):
            .noteOff(note: note, releaseVelocity: .init(midi1: velocity))
        case let .controlChange(controller, value):
            .controller(.controlChange(number: controller, value: .init(midi1: value)))
        case let .pitchBend(value):
            .controller(.pitchBend(value: .init(midi14: value)))
        case let .programChange(program):
            .controller(.programChange(program: program))
        case let .channelPressure(value):
            .controller(.channelPressure(value: .init(midi1: value)))
        case let .polyPressure(note, value):
            .controller(.polyPressure(note: note, value: .init(midi1: value)))
        }
    }

    private func observationEvent(_ event: MIDI2InputEvent.Kind) -> PerformanceObservation.Event {
        switch event {
        case let .noteOn(note, velocity):
            .noteOn(note: note, velocity: .init(midi2: velocity))
        case let .noteOff(note, velocity):
            .noteOff(note: note, releaseVelocity: .init(midi2: velocity))
        case let .controlChange(controller, value):
            .controller(.controlChange(number: controller, value: .init(rawValue: value)))
        case let .pitchBend(value):
            .controller(.pitchBend(value: .init(rawValue: value)))
        case let .programChange(program):
            .controller(.programChange(program: program))
        case let .channelPressure(value):
            .controller(.channelPressure(value: .init(rawValue: value)))
        case let .polyPressure(note, value):
            .controller(.polyPressure(note: note, value: .init(rawValue: value)))
        }
    }
}
