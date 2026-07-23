import Foundation

enum RecordingTakeLibraryPathsError: Error {
    case documentsUnavailable
}

enum RecordingTakeLibraryLayout {
    static let rootDirectoryName = "TakeLibrary"
    static let takesFileName = "takes.json"
}

struct RecordingTakeLibraryPaths {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func rootDirectoryURL() throws -> URL {
        try documentsDirectoryURL()
            .appending(path: RecordingTakeLibraryLayout.rootDirectoryName, directoryHint: .isDirectory)
    }

    func takesFileURL() throws -> URL {
        try rootDirectoryURL()
            .appending(path: RecordingTakeLibraryLayout.takesFileName)
    }

    func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: rootDirectoryURL(), withIntermediateDirectories: true)
    }

    private func documentsDirectoryURL() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw RecordingTakeLibraryPathsError.documentsUnavailable
        }
        return documentsURL
    }
}

protocol RecordingTakeStoreProtocol {
    func load() throws -> [RecordingTake]
    func save(_ takes: [RecordingTake]) throws
}

struct RecordingTakeStore: RecordingTakeStoreProtocol {
    private let fileManager: FileManager
    private let paths: RecordingTakeLibraryPaths

    init(fileManager: FileManager = .default, paths: RecordingTakeLibraryPaths? = nil) {
        self.fileManager = fileManager
        self.paths = paths ?? RecordingTakeLibraryPaths(fileManager: fileManager)
    }

    func load() throws -> [RecordingTake] {
        try paths.ensureDirectoriesExist()
        let takesFileURL = try paths.takesFileURL()

        guard fileManager.fileExists(atPath: takesFileURL.path()) else {
            return []
        }

        let data = try Data(contentsOf: takesFileURL)
        if data.isEmpty {
            return []
        }

        if let text = String(data: data, encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([RecordingTake].self, from: data)
        } catch {
            try CorruptedFileQuarantine.move(takesFileURL, fileManager: fileManager)
            return []
        }
    }

    func save(_ takes: [RecordingTake]) throws {
        try paths.ensureDirectoriesExist()
        let takesFileURL = try paths.takesFileURL()

        for take in takes {
            try take.metadata.validatePrivacy()
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(takes)
        try data.write(to: takesFileURL, options: .atomic)
    }
}

struct RecordingMIDIExport: Equatable {
    let data: Data
    let fileName: String
}

protocol RecordingMIDIExportServiceProtocol {
    func makeMIDIExport(from take: RecordingTake) throws -> RecordingMIDIExport
}

struct RecordingMIDIExportService: RecordingMIDIExportServiceProtocol {
    private let sequenceAdapter: RecordingTakeSequenceAdapter

    init(sequenceAdapter: RecordingTakeSequenceAdapter = RecordingTakeSequenceAdapter()) {
        self.sequenceAdapter = sequenceAdapter
    }

    func makeMIDIExport(from take: RecordingTake) throws -> RecordingMIDIExport {
        let sequence = try sequenceAdapter.buildSequence(from: take)
        return RecordingMIDIExport(
            data: sequence.midiData,
            fileName: "\(Self.sanitizedFileBaseName(take.name)).mid"
        )
    }

    private static func sanitizedFileBaseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = trimmed.isEmpty ? "Recording" : trimmed
        return fallbackName
            .replacing("/", with: "-")
            .replacing(":", with: "-")
    }
}

struct MIDIRecordingAdapter {
    private var observationAdapter = MIDIPerformanceObservationAdapter()
    private var generation: UInt64 = 0

    init() {}

    mutating func beginRecording() {
        generation &+= 1
        observationAdapter.resetClockCalibration()
    }

    mutating func observation(for event: MIDI1InputEvent) -> PerformanceObservation {
        observationAdapter.observation(for: event, generation: generation)
    }

    mutating func observation(for event: MIDI2InputEvent) -> PerformanceObservation {
        observationAdapter.observation(for: event, generation: generation)
    }

    mutating func record(_ observation: PerformanceObservation, into recorder: inout RecordingTakeRecorder) {
        recorder.record(observation)
    }

    mutating func record(event: MIDI1InputEvent, into recorder: inout RecordingTakeRecorder) {
        record(observation(for: event), into: &recorder)
    }

    mutating func record(event: MIDI2InputEvent, into recorder: inout RecordingTakeRecorder) {
        record(observation(for: event), into: &recorder)
    }
}

struct RecordingTakeSequenceAdapter {
    private let builder: PracticeSequencerSequenceBuilder

    init(builder: PracticeSequencerSequenceBuilder = PracticeSequencerSequenceBuilder()) {
        self.builder = builder
    }

    func makeMIDISchedule(from take: RecordingTake) -> [PracticeSequencerMIDIEvent] {
        take.events.map { event in
            switch event.kind {
            case let .noteOn(midi, velocity):
                let clampedMIDINote = max(0, min(127, midi))
                let clampedVelocity = max(0, min(127, velocity))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .noteOn(midi: clampedMIDINote, velocity: UInt8(clampedVelocity))
                )
            case let .noteOff(midi):
                let clampedMIDINote = max(0, min(127, midi))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .noteOff(midi: clampedMIDINote)
                )
            case let .controlChange(controller, value):
                let clampedController = max(0, min(127, controller))
                let clampedValue = max(0, min(127, value))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .controlChange(controller: UInt8(clampedController), value: UInt8(clampedValue))
                )
            case let .pitchBend(value):
                let clampedValue = max(0, min(16383, value))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .pitchBend(value: UInt16(clampedValue))
                )
            case let .programChange(program):
                let clampedProgram = max(0, min(127, program))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .programChange(program: UInt8(clampedProgram))
                )
            case let .channelPressure(value):
                let clampedValue = max(0, min(127, value))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .channelPressure(value: UInt8(clampedValue))
                )
            case let .polyPressure(midi, value):
                let clampedMIDINote = max(0, min(127, midi))
                let clampedValue = max(0, min(127, value))
                return PracticeSequencerMIDIEvent(
                    timeSeconds: event.time,
                    kind: .polyPressure(midi: clampedMIDINote, value: UInt8(clampedValue))
                )
            }
        }
    }

    func buildSequence(from take: RecordingTake) throws -> PracticeSequencerSequence {
        let schedule = makeMIDISchedule(from: take)
        return try builder.buildSequence(from: schedule)
    }
}

extension RecordingTake {
    func alignmentObservations() -> [PerformanceObservation]? {
        let observations = events.compactMap { event in
            event.observation?.rebasedForAlignment(at: event.time)
        }
        return observations.count == events.count ? observations : nil
    }
}

private extension PerformanceObservation {
    func rebasedForAlignment(at seconds: TimeInterval) -> Self {
        let instant = PerformanceMonotonicInstant(seconds: seconds)
        return Self(
            id: id,
            source: source,
            timing: .init(
                host: instant,
                source: nil,
                correctedHost: instant,
                mapping: nil,
                provenance: .hostOnly
            ),
            event: event,
            onsetVelocity: onsetVelocity,
            channel: channel,
            group: group,
            hand: hand,
            finger: finger,
            confidence: confidence,
            calibrationReference: calibrationReference
        )
    }
}
