import Foundation
@testable import HappyPianistAVP
import Testing

@Test
func takeStoreLoadReturnsEmptyWhenFileMissing() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)
    let takes = try store.load()
    #expect(takes.isEmpty)
}

@Test
func takeStoreSaveAndLoadRoundTrip() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)
    let songID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

    let take = RecordingTake(
        name: "Test Take",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        metadata: RecordingTakeMetadata(
            scoreIdentity: ScorePerformanceSourceIdentity(
                songID: songID,
                scoreRevision: "sha256:score-revision",
                logicalInstrumentID: "P1:piano"
            ),
            inputSources: [RecordingInputSourceDescriptor(
                kind: .midi2,
                id: "endpoint:42",
                capabilities: .midi
            )],
            clockMapping: PerformanceClockMapping(
                sourceClockID: "mach-absolute-time",
                offsetSeconds: 0.25,
                rate: 1.0001,
                sampleCount: 12,
                estimatedLatencySeconds: 0.012,
                provenance: .offsetAndDriftSamples
            ),
            latencyCorrectionSeconds: 0.012,
            calibrationVersion: "midi-latency-v2"
        ),
        events: [
            RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )

    try store.save([take])
    let loaded = try store.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].name == "Test Take")
    #expect(loaded[0].schemaVersion == RecordingTake.currentSchemaVersion)
    #expect(loaded[0].metadata == take.metadata)
    #expect(loaded[0].events.count == 2)
    #expect(loaded[0].events[0].kind == .noteOn(midi: 60, velocity: 90))
    #expect(loaded[0].events[1].kind == .noteOff(midi: 60))
}

@Test
func recordingTakeRejectsPreviousSchemaVersion() throws {
    let encoded = try JSONEncoder().encode(RecordingTake(name: "Legacy", events: []))
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object["schemaVersion"] = RecordingTake.currentSchemaVersion - 1
    let legacy = try JSONSerialization.data(withJSONObject: object)

    do {
        _ = try JSONDecoder().decode(RecordingTake.self, from: legacy)
        Issue.record("Previous recording schema must not decode through a compatibility path")
    } catch let error as RecordingTakeCodingError {
        #expect(error == .unsupportedSchemaVersion(RecordingTake.currentSchemaVersion - 1))
    }
}

@Test
func performanceObservationSourceRequiresRole() throws {
    let source = PerformanceObservation.Source(kind: .midi1, id: "midi:test", generation: 1)
    let encoded = try JSONEncoder().encode(source)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "role")
    let legacy = try JSONSerialization.data(withJSONObject: object)

    do {
        _ = try JSONDecoder().decode(PerformanceObservation.Source.self, from: legacy)
        Issue.record("Source role must be explicit at the persistence boundary")
    } catch let error as DecodingError {
        guard case let .keyNotFound(key, _) = error else {
            Issue.record("Expected missing role key, got \(error)")
            return
        }
        #expect(key.stringValue == "role")
    }
}

@Test
func takeStoreRejectsAbsolutePathsAndRawScoreMetadata() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)
    let take = RecordingTake(
        name: "Unsafe",
        metadata: RecordingTakeMetadata(
            inputSources: [RecordingInputSourceDescriptor(
                kind: .midi1,
                id: "/Users/private/score.musicxml",
                capabilities: .midi
            )],
            calibrationVersion: "<score-partwise>raw score</score-partwise>"
        ),
        events: []
    )

    do {
        try store.save([take])
        Issue.record("Unsafe metadata should not be encoded")
    } catch let error as RecordingTakeCodingError {
        #expect(error == .unsafeMetadata(field: "inputSources.id"))
    }

    let rawScoreTake = RecordingTake(
        name: "Unsafe",
        metadata: RecordingTakeMetadata(
            inputSources: [RecordingInputSourceDescriptor(
                kind: .midi1,
                id: "endpoint:42",
                capabilities: .midi
            )],
            calibrationVersion: "<score-partwise>raw score</score-partwise>"
        ),
        events: []
    )
    do {
        try store.save([rawScoreTake])
        Issue.record("Raw score metadata should not be encoded")
    } catch let error as RecordingTakeCodingError {
        #expect(error == .unsafeMetadata(field: "calibrationVersion"))
    }
    #expect(fileManager.fileExists(atPath: try paths.takesFileURL().path()) == false)
}

@Test
func takeStoreRejectsPrivatePathsInsideObservationEvidence() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }
    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)
    let host = PerformanceMonotonicInstant(seconds: 1)
    let observation = PerformanceObservation(
        source: .init(kind: .midi1, id: "/Users/private/device", generation: 1),
        timing: PerformanceClockReading(
            host: host,
            source: nil,
            correctedHost: host,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .noteOn(note: 60, velocity: .init(midi1: 90)),
        channel: 1,
        group: 0
    )
    let take = RecordingTake(
        name: "Unsafe",
        events: [RecordingTakeEvent(
            time: 0,
            kind: .noteOn(midi: 60, velocity: 90),
            observation: observation
        )]
    )

    do {
        try store.save([take])
        Issue.record("Private path in event evidence should not be encoded")
    } catch let error as RecordingTakeCodingError {
        #expect(error == .unsafeMetadata(field: "events.observation.source.id"))
    }
}

@Test
func takeStoreLoadReturnsEmptyWhenFileIsEmpty() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    try paths.ensureDirectoriesExist()
    let takesFileURL = try paths.takesFileURL()
    try Data().write(to: takesFileURL)

    let takes = try store.load()
    #expect(takes.isEmpty)
}

@Test
func takeStoreSaveAndLoadMultipleTakes() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let takes = [
        RecordingTake(name: "Take 1", events: [RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 60, velocity: 90))]),
        RecordingTake(name: "Take 2", events: [RecordingTakeEvent(time: 0.0, kind: .noteOn(midi: 64, velocity: 80))]),
    ]

    try store.save(takes)
    let loaded = try store.load()

    #expect(loaded.count == 2)
    #expect(loaded[0].name == "Take 1")
    #expect(loaded[1].name == "Take 2")
}

@Test
func takeStoreClearAndReload() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)

    let take = RecordingTake(name: "Test", events: [])
    try store.save([take])
    try store.save([])

    let loaded = try store.load()
    #expect(loaded.isEmpty)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private final class TestDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .documentDirectory {
            return [documentsURL]
        }
        return super.urls(for: directory, in: domainMask)
    }
}

@Test
func takeStoreQuarantinesCorruptFileAndRecoversPersistence() throws {
    let documentsURL = try makeTemporaryDirectory(prefix: "RecordingTakeStoreTests")
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TestDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)
    try paths.ensureDirectoriesExist()
    let takesFileURL = try paths.takesFileURL()
    let corruptData = Data("{not-json".utf8)
    try corruptData.write(to: takesFileURL)

    #expect(try store.load().isEmpty)
    #expect(fileManager.fileExists(atPath: takesFileURL.path()) == false)

    let quarantinedURLs = try fileManager.contentsOfDirectory(
        at: takesFileURL.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("takes.corrupt-") }
    #expect(quarantinedURLs.count == 1)
    #expect(try Data(contentsOf: #require(quarantinedURLs.first)) == corruptData)

    let replacement = RecordingTake(name: "Recovered", events: [])
    try store.save([replacement])
    #expect(try store.load().map(\.name) == ["Recovered"])
}
