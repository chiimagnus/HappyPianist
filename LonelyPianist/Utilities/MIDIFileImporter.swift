import AudioToolbox
import Foundation

enum MIDIFileImporterError: LocalizedError, Equatable {
    case openFailed(OSStatus)
    case loadFailed(OSStatus)
    case secondsConversionFailed(OSStatus)
    case empty

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
        }
    }
}

struct MIDIFileImporter {
    static func importNotes(from url: URL) throws -> (notes: [RecordedNote], durationSec: TimeInterval) {
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
        var maxEndSec: TimeInterval = 0

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
                    let end = startSec + duration
                    maxEndSec = max(maxEndSec, end)

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

        notes.sort { lhs, rhs in
            if lhs.startOffsetSec != rhs.startOffsetSec { return lhs.startOffsetSec < rhs.startOffsetSec }
            if lhs.note != rhs.note { return lhs.note < rhs.note }
            if lhs.channel != rhs.channel { return lhs.channel < rhs.channel }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        return (notes: notes, durationSec: maxEndSec)
    }

    private static func seconds(forBeats beats: MusicTimeStamp, in sequence: MusicSequence) throws -> TimeInterval {
        var seconds: Float64 = 0
        let status = MusicSequenceGetSecondsForBeats(sequence, beats, &seconds)
        guard status == noErr else {
            throw MIDIFileImporterError.secondsConversionFailed(status)
        }
        return TimeInterval(seconds)
    }
}

