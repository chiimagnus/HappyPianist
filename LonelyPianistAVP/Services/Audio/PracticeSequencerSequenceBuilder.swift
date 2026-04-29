import AudioToolbox
import Foundation

nonisolated struct PracticeSequencerMIDIEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case noteOn(midi: Int, velocity: UInt8)
        case noteOff(midi: Int)
        case controlChange(controller: UInt8, value: UInt8)
    }

    let timeSeconds: TimeInterval
    let kind: Kind
}

nonisolated enum PracticeSequencerSequenceBuilderError: LocalizedError, Equatable, Sendable {
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

nonisolated struct PracticeSequencerSequenceBuilder: Sendable {
    private let midiChannel: UInt8

    init(midiChannel: UInt8 = 0) {
        self.midiChannel = midiChannel
    }

    func buildAudioEventSchedule(
        timeline: AutoplayPerformanceTimeline,
        tempoMap: MusicXMLTempoMap,
        startTick: Int,
        initialSustainPedalDown: Bool = false,
        endTick: Int? = nil
    ) -> [PracticeSequencerMIDIEvent] {
        let baseTick = max(0, startTick)
        let baseSeconds = tempoMap.timeSeconds(atTick: baseTick)

        let startIndex = timeline.firstEventIndex(atOrAfter: baseTick)
        var pausePrefixSeconds: TimeInterval = 0

        var schedule: [PracticeSequencerMIDIEvent] = []
        schedule.reserveCapacity(128)

        if initialSustainPedalDown {
            schedule.append(
                PracticeSequencerMIDIEvent(
                    timeSeconds: 0,
                    kind: .controlChange(controller: 64, value: 127)
                )
            )
        }

        for event in timeline.events[startIndex...] {
            if let endTick, event.tick >= endTick { break }

            switch event.kind {
                case let .pauseSeconds(seconds):
                    pausePrefixSeconds += seconds

                case let .noteOff(midi):
                    schedule.append(
                        PracticeSequencerMIDIEvent(
                            timeSeconds: tempoMap.timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds,
                            kind: .noteOff(midi: midi)
                        )
                    )

                case .pedalDown:
                    schedule.append(
                        PracticeSequencerMIDIEvent(
                            timeSeconds: tempoMap.timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds,
                            kind: .controlChange(controller: 64, value: 127)
                        )
                    )

                case .pedalUp:
                    schedule.append(
                        PracticeSequencerMIDIEvent(
                            timeSeconds: tempoMap.timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds,
                            kind: .controlChange(controller: 64, value: 0)
                        )
                    )

                case let .noteOn(midi, velocity):
                    schedule.append(
                        PracticeSequencerMIDIEvent(
                            timeSeconds: tempoMap.timeSeconds(atTick: event.tick) - baseSeconds + pausePrefixSeconds,
                            kind: .noteOn(midi: midi, velocity: velocity)
                        )
                    )

                case .advanceStep, .advanceGuide:
                    continue
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
            return tieBreaker(lhs.kind) < tieBreaker(rhs.kind)
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
            durationSeconds: durationSeconds
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
        }
    }

    private func eventPriority(_ kind: PracticeSequencerMIDIEvent.Kind) -> Int {
        switch kind {
            case .controlChange:
                0
            case .noteOff:
                1
            case .noteOn:
                2
        }
    }

    private func tieBreaker(_ kind: PracticeSequencerMIDIEvent.Kind) -> String {
        switch kind {
            case let .noteOn(midi, velocity):
                return "on-\(midi)-\(velocity)"
            case let .noteOff(midi):
                return "off-\(midi)"
            case let .controlChange(controller, value):
                return "cc-\(controller)-\(value)"
        }
    }
}
