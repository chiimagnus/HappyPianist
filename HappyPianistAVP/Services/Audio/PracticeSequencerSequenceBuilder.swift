import AudioToolbox
import Foundation

struct PracticeSequencerMIDIEvent: Equatable {
    enum Kind: Equatable {
        case noteOn(midi: Int, velocity: UInt8)
        case noteOff(midi: Int)
        case controlChange(controller: UInt8, value: UInt8)
        case pitchBend(value: UInt16)
        case programChange(program: UInt8)
        case channelPressure(value: UInt8)
        case polyPressure(midi: Int, value: UInt8)
    }

    let sourceEventID: String?
    let timeSeconds: TimeInterval
    let kind: Kind

    init(
        sourceEventID: String? = nil,
        timeSeconds: TimeInterval,
        kind: Kind
    ) {
        self.sourceEventID = sourceEventID
        self.timeSeconds = timeSeconds
        self.kind = kind
    }
}

enum PracticeSequencerSequenceBuilderError: LocalizedError, Equatable {
    case musicSequenceCreateFailed
    case musicTrackCreateFailed(status: OSStatus)
    case tempoTrackMissing
    case trackEventInsertFailed(status: OSStatus)
    case midiExportFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .musicSequenceCreateFailed:
            "MusicSequence 创建失败。"
        case let .musicTrackCreateFailed(status):
            "MusicTrack 创建失败：\(status)"
        case .tempoTrackMissing:
            "Tempo track 缺失。"
        case let .trackEventInsertFailed(status):
            "写入 MIDI event 失败：\(status)"
        case let .midiExportFailed(status):
            "导出 MIDI data 失败：\(status)"
        }
    }
}

struct PracticeSequencerSequenceBuilder {
    private let midiChannel: UInt8

    init(midiChannel: UInt8 = 0) {
        self.midiChannel = midiChannel
    }

    func buildPerformanceEventSchedule(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        leadInSeconds: TimeInterval = 0,
        endTick: Int? = nil
    ) -> [PracticeSequencerMIDIEvent] {
        let baseTick = max(0, startTick)
        let baseSeconds = tempoMap.timeSeconds(atTick: baseTick)

        let startIndex = timeline.firstEventIndex(atOrAfter: baseTick)
        var pausePrefixSeconds: TimeInterval = 0

        var schedule: [PracticeSequencerMIDIEvent] = []
        schedule.reserveCapacity(128)

        let controllersAtBaseTick = Set(timeline.events[startIndex...].compactMap { event -> UInt8? in
            guard event.tick == baseTick else { return nil }
            if case let .controlChange(controller, _) = event.kind { return controller }
            return nil
        })
        let controllerContext = Dictionary(
            grouping: timeline.events[..<startIndex].compactMap { event -> (UInt8, AutoplayPerformanceTimeline.Event)? in
                if case let .controlChange(controller, _) = event.kind { return (controller, event) }
                return nil
            },
            by: \.0
        )
        .compactMap { controller, events in events.last.map { (controller, $0.1) } }
        .filter { controllersAtBaseTick.contains($0.0) == false }
        .sorted { $0.0 < $1.0 }

        for (_, event) in controllerContext {
            guard case let .controlChange(controller, value) = event.kind else { continue }
            schedule.append(
                PracticeSequencerMIDIEvent(
                    sourceEventID: event.sourceEventID,
                    timeSeconds: max(0, leadInSeconds),
                    kind: .controlChange(controller: controller, value: value)
                )
            )
        }

        var openNotes: [String: Int] = [:]
        for event in timeline.events[startIndex...] {
            if let endTick {
                if event.tick > endTick { break }
                if event.tick == endTick {
                    switch event.kind {
                    case .pauseSeconds, .noteOff:
                        break
                    case .controlChange, .tempo, .noteOn, .advanceStep, .advanceGuide:
                        continue
                    }
                }
            }

            switch event.kind {
            case let .pauseSeconds(seconds):
                pausePrefixSeconds += seconds

            case let .noteOff(midi):
                schedule.append(
                    PracticeSequencerMIDIEvent(
                        sourceEventID: event.sourceEventID,
                        timeSeconds: tempoMap
                            .timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds + leadInSeconds,
                        kind: .noteOff(midi: midi)
                    )
                )
                openNotes.removeValue(forKey: event.sourceEventID ?? "timeline:\(event.id)")

            case let .controlChange(controller, value):
                schedule.append(
                    PracticeSequencerMIDIEvent(
                        sourceEventID: event.sourceEventID,
                        timeSeconds: tempoMap
                            .timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds + leadInSeconds,
                        kind: .controlChange(controller: controller, value: value)
                    )
                )

            case let .noteOn(midi, velocity):
                schedule.append(
                    PracticeSequencerMIDIEvent(
                        sourceEventID: event.sourceEventID,
                        timeSeconds: tempoMap
                            .timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds + leadInSeconds,
                        kind: .noteOn(midi: midi, velocity: velocity)
                    )
                )
                openNotes[event.sourceEventID ?? "timeline:\(event.id)"] = midi

            case .tempo, .advanceStep, .advanceGuide:
                continue
            }
        }

        if let endTick {
            let endSeconds = tempoMap.timeSeconds(atTick: endTick) - baseSeconds
                + pausePrefixSeconds + leadInSeconds
            for (sourceEventID, midi) in openNotes.sorted(by: { $0.key < $1.key }) {
                schedule.append(PracticeSequencerMIDIEvent(
                    sourceEventID: sourceEventID,
                    timeSeconds: endSeconds,
                    kind: .noteOff(midi: midi)
                ))
            }
        }

        return schedule
    }

    func buildSequence(from schedule: [PracticeSequencerMIDIEvent]) throws -> PracticeSequencerSequence {
        var musicSequence: MusicSequence?
        NewMusicSequence(&musicSequence)
        guard let musicSequence else {
            throw PracticeSequencerSequenceBuilderError.musicSequenceCreateFailed
        }

        var tempoTrack: MusicTrack?
        MusicSequenceGetTempoTrack(musicSequence, &tempoTrack)
        guard let tempoTrack else {
            throw PracticeSequencerSequenceBuilderError.tempoTrackMissing
        }
        let tempoStatus = MusicTrackNewExtendedTempoEvent(tempoTrack, 0, 60)
        guard tempoStatus == noErr else {
            throw PracticeSequencerSequenceBuilderError.trackEventInsertFailed(status: tempoStatus)
        }

        var track: MusicTrack?
        let newTrackStatus = MusicSequenceNewTrack(musicSequence, &track)
        guard newTrackStatus == noErr, let track else {
            throw PracticeSequencerSequenceBuilderError.musicTrackCreateFailed(status: newTrackStatus)
        }

        let sortedSchedule = schedule.sorted { lhs, rhs in
            if lhs.timeSeconds != rhs.timeSeconds { return lhs.timeSeconds < rhs.timeSeconds }
            if eventPriority(lhs.kind) != eventPriority(rhs.kind) {
                return eventPriority(lhs.kind) < eventPriority(rhs.kind)
            }
            return tieBreaker(lhs) < tieBreaker(rhs)
        }

        var durationSeconds: TimeInterval = 0
        for event in sortedSchedule {
            durationSeconds = max(durationSeconds, event.timeSeconds)

            var message = midiChannelMessage(for: event.kind)
            let timeStamp = MusicTimeStamp(max(0, event.timeSeconds))
            let insertStatus = MusicTrackNewMIDIChannelEvent(track, timeStamp, &message)
            guard insertStatus == noErr else {
                throw PracticeSequencerSequenceBuilderError.trackEventInsertFailed(status: insertStatus)
            }
        }

        var exportedData: Unmanaged<CFData>?
        let exportStatus = MusicSequenceFileCreateData(
            musicSequence,
            .midiType,
            .eraseFile,
            Int16(MusicXMLTempoMap.ticksPerQuarter),
            &exportedData
        )
        guard exportStatus == noErr, let exportedData else {
            throw PracticeSequencerSequenceBuilderError.midiExportFailed(status: exportStatus)
        }

        return PracticeSequencerSequence(
            midiData: exportedData.takeRetainedValue() as Data,
            durationSeconds: durationSeconds,
            events: sortedSchedule
        )
    }

    private func midiChannelMessage(for kind: PracticeSequencerMIDIEvent.Kind) -> MIDIChannelMessage {
        switch kind {
        case let .noteOn(midi, velocity):
            return MIDIChannelMessage(
                status: UInt8(0x90 | midiChannel),
                data1: UInt8(clamping: midi),
                data2: velocity,
                reserved: 0
            )

        case let .noteOff(midi):
            return MIDIChannelMessage(
                status: UInt8(0x80 | midiChannel),
                data1: UInt8(clamping: midi),
                data2: 0,
                reserved: 0
            )

        case let .controlChange(controller, value):
            return MIDIChannelMessage(
                status: UInt8(0xB0 | midiChannel),
                data1: controller,
                data2: value,
                reserved: 0
            )

        case let .pitchBend(value):
            let clamped = UInt16(clamping: value)
            let lsb = UInt8(clamped & 0x7F)
            let msb = UInt8((clamped >> 7) & 0x7F)
            return MIDIChannelMessage(
                status: UInt8(0xE0 | midiChannel),
                data1: lsb,
                data2: msb,
                reserved: 0
            )

        case let .programChange(program):
            return MIDIChannelMessage(
                status: UInt8(0xC0 | midiChannel),
                data1: program,
                data2: 0,
                reserved: 0
            )

        case let .channelPressure(value):
            return MIDIChannelMessage(
                status: UInt8(0xD0 | midiChannel),
                data1: value,
                data2: 0,
                reserved: 0
            )

        case let .polyPressure(midi, value):
            return MIDIChannelMessage(
                status: UInt8(0xA0 | midiChannel),
                data1: UInt8(clamping: midi),
                data2: value,
                reserved: 0
            )
        }
    }

    private func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
        case .controlChange:
            0
        case .programChange, .pitchBend, .channelPressure, .polyPressure:
            1
        case .noteOff:
            2
        case .noteOn:
            3
        }
    }

    private func tieBreaker(_ event: PracticeSequencerMIDIEvent) -> String {
        let kind = switch event.kind {
        case let .noteOn(midi, velocity):
            "on-\(midi)-\(velocity)"
        case let .noteOff(midi):
            "off-\(midi)"
        case let .controlChange(controller, value):
            "cc-\(controller)-\(value)"
        case let .pitchBend(value):
            "pb-\(value)"
        case let .programChange(program):
            "pc-\(program)"
        case let .channelPressure(value):
            "cp-\(value)"
        case let .polyPressure(midi, value):
            "pp-\(midi)-\(value)"
        }
        return "\(kind)-\(event.sourceEventID ?? "unresolved")"
    }
}
