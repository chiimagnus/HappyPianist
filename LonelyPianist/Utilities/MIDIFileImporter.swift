import AudioToolbox
import Foundation

enum MIDIFileImporterError: LocalizedError, Equatable {
    case openFailed(OSStatus)
    case loadFailed(OSStatus)
    case secondsConversionFailed(OSStatus)
    case empty
    case emptyAfterFiltering

    var errorDescription: String? {
        switch self {
        case .openFailed(let status):
            return "Failed to open MIDI sequence (OSStatus=\(status))."
        case .loadFailed(let status):
            return "Failed to load MIDI file (OSStatus=\(status))."
        case .secondsConversionFailed(let status):
            return "Failed to convert beats to seconds (OSStatus=\(status))."
        case .empty:
            return "No notes found in MIDI file."
        case .emptyAfterFiltering:
            return "No notes left after applying import filters."
        }
    }
}

struct MIDIFileImportOptions: Sendable, Equatable {
    var excludedChannels: Set<Int>
    var remapAllChannelsTo: Int?
    var clampNoteRange: ClosedRange<Int>?
    var minimumVelocity: Int
    var minimumDurationSec: TimeInterval

    static let `default` = MIDIFileImportOptions(
        excludedChannels: [],
        remapAllChannelsTo: nil,
        clampNoteRange: nil,
        minimumVelocity: 1,
        minimumDurationSec: 0.01
    )

    static let pianoOnly = MIDIFileImportOptions(
        excludedChannels: [10],
        remapAllChannelsTo: 1,
        clampNoteRange: 21...108,
        minimumVelocity: 8,
        minimumDurationSec: 0.04
    )
}

struct MIDIFileImporter {
    static func importNotes(
        from url: URL,
        options: MIDIFileImportOptions = .default
    ) throws -> (notes: [RecordedNote], durationSec: TimeInterval) {
        var sequence: MusicSequence?
        var status = NewMusicSequence(&sequence)
        guard status == noErr, let sequence else {
            throw MIDIFileImporterError.openFailed(status)
        }

        status = MusicSequenceFileLoad(
            sequence,
            url as CFURL,
            .midiType,
            MusicSequenceLoadFlags.smf_ChannelsToTracks
        )
        guard status == noErr else {
            throw MIDIFileImporterError.loadFailed(status)
        }

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        var notes: [RecordedNote] = []
        notes.reserveCapacity(1024)

        for index in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, index, &track)
            guard let track else { continue }

            var iterator: MusicEventIterator?
            NewMusicEventIterator(track, &iterator)
            guard let iterator else { continue }
            defer { DisposeMusicEventIterator(iterator) }

            var hasEvent: DarwinBoolean = false
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

            while hasEvent.boolValue {
                var timeStamp: MusicTimeStamp = 0
                var eventType: MusicEventType = 0
                var eventData: UnsafeRawPointer?
                var eventDataSize: UInt32 = 0

                MusicEventIteratorGetEventInfo(iterator, &timeStamp, &eventType, &eventData, &eventDataSize)

                if eventType == kMusicEventType_MIDINoteMessage, let eventData {
                    let message = eventData.load(as: MIDINoteMessage.self)
                    let startBeat = timeStamp
                    let endBeat = timeStamp + MusicTimeStamp(message.duration)

                    let startSec = try seconds(forBeats: startBeat, in: sequence)
                    let endSec = try seconds(forBeats: endBeat, in: sequence)

                    let clampedNote = Int(max(0, min(127, message.note)))
                    let clampedVelocity = Int(max(0, min(127, message.velocity)))
                    let channel = Int(message.channel) + 1

                    let duration = max(0.01, endSec - startSec)
                    notes.append(
                        RecordedNote(
                            id: UUID(),
                            note: clampedNote,
                            velocity: clampedVelocity,
                            channel: max(1, channel),
                            startOffsetSec: max(0, startSec),
                            durationSec: duration
                        )
                    )
                }

                MusicEventIteratorNextEvent(iterator)
                MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
            }
        }

        guard !notes.isEmpty else {
            throw MIDIFileImporterError.empty
        }

        let filtered = applyFilters(notes: notes, options: options)
        guard !filtered.isEmpty else {
            throw MIDIFileImporterError.emptyAfterFiltering
        }

        let durationSec: TimeInterval = filtered.reduce(0) { partial, note in
            max(partial, note.startOffsetSec + max(options.minimumDurationSec, note.durationSec))
        }

        var sorted = filtered
        sorted.sort { lhs, rhs in
            if lhs.startOffsetSec != rhs.startOffsetSec { return lhs.startOffsetSec < rhs.startOffsetSec }
            if lhs.note != rhs.note { return lhs.note < rhs.note }
            if lhs.channel != rhs.channel { return lhs.channel < rhs.channel }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return (notes: sorted, durationSec: durationSec)
    }

    private static func seconds(forBeats beats: MusicTimeStamp, in sequence: MusicSequence) throws -> TimeInterval {
        var seconds: Float64 = 0
        let status = MusicSequenceGetSecondsForBeats(sequence, beats, &seconds)
        guard status == noErr else {
            throw MIDIFileImporterError.secondsConversionFailed(status)
        }
        return TimeInterval(seconds)
    }

    private static func applyFilters(
        notes: [RecordedNote],
        options: MIDIFileImportOptions
    ) -> [RecordedNote] {
        var filtered = notes

        if !options.excludedChannels.isEmpty {
            filtered.removeAll { options.excludedChannels.contains($0.channel) }
        }

        if let clamp = options.clampNoteRange {
            filtered.removeAll { !clamp.contains($0.note) }
        }

        let minVel = max(0, min(127, options.minimumVelocity))
        if minVel > 0 {
            filtered.removeAll { $0.velocity < minVel }
        }

        let minDur = max(0, options.minimumDurationSec)
        if minDur > 0 {
            filtered.removeAll { $0.durationSec < minDur }
        }

        if let remap = options.remapAllChannelsTo {
            let target = max(1, min(16, remap))
            filtered = filtered.map { note in
                var note = note
                note.channel = target
                return note
            }
        }

        return filtered
    }
}
