import Foundation

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
