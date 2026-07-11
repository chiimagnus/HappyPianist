import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func cancelledPreparationDoesNotProducePreparedPractice() async throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "cancelled-\(UUID().uuidString).musicxml")
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0"><part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list><part id="P1"><measure number="1"><attributes><divisions>1</divisions></attributes><note><rest/><duration>1</duration></note></measure></part></score-partwise>
    """
    try Data(xml.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let service = PracticePreparationService()
    let task = Task {
        try await service.prepare(
            songID: UUID(),
            from: url,
            file: ImportedMusicXMLFile(fileName: "Cancelled", storedURL: url, importedAt: .now)
        )
    }
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Cancelled preparation unexpectedly completed")
    } catch is CancellationError {
        // Expected.
    }
}
