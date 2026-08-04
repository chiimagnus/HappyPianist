import Foundation
import Practice
import Testing

@Test func recorderClosesNotesPreservesMIDIProvenanceAndDropsTargetAudio() {
    var recorder = RecordingTakeRecorder()
    recorder.start(now: 10)
    recorder.record(targetAudioObservation(at: 10.1))
    recorder.record(midiObservation(at: 10.2, event: .noteOn(note: 60, velocity: .init(midi1: 96))))

    let take = recorder.stop(now: 11, createdAt: Date(timeIntervalSince1970: 0))

    #expect(take.events.map(\.kind) == [.noteOn(midi: 60, velocity: 96), .noteOff(midi: 60)])
    #expect(take.events.last?.time == 1)
    #expect(take.metadata.inputSources == [RecordingInputSourceDescriptor(
        kind: .midi1,
        id: "endpoint:42",
        capabilities: .midi
    )])
}

@Test func takeStoreQuarantinesCorruptionAndRejectsUnsafeMetadata() throws {
    let documentsURL = try makeTakeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: documentsURL) }

    let fileManager = TakeDocumentsFileManager(documentsURL: documentsURL)
    let paths = RecordingTakeLibraryPaths(fileManager: fileManager)
    let store = RecordingTakeStore(fileManager: fileManager, paths: paths)
    try paths.ensureDirectoriesExist()
    let takesURL = try paths.takesFileURL()
    try Data("{not-json".utf8).write(to: takesURL)

    #expect(try store.load().isEmpty)
    #expect(fileManager.fileExists(atPath: takesURL.path()) == false)
    let quarantined = try fileManager.contentsOfDirectory(
        at: takesURL.deletingLastPathComponent(),
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("takes.corrupt-") }
    #expect(quarantined.count == 1)

    let unsafeTake = RecordingTake(
        name: "Unsafe",
        metadata: RecordingTakeMetadata(inputSources: [
            RecordingInputSourceDescriptor(kind: .midi1, id: "/private/device", capabilities: .midi),
        ]),
        events: []
    )
    do {
        try store.save([unsafeTake])
        Issue.record("Unsafe metadata must not reach take storage")
    } catch let error as RecordingTakeCodingError {
        #expect(error == .unsafeMetadata(field: "inputSources.id"))
    }

    let recoveredTake = RecordingTake(name: "Recovered", events: [])
    try store.save([recoveredTake])
    #expect(try store.load().map(\.name) == ["Recovered"])
}

@Test func takeMIDIExportUsesCanonicalSequenceAndSafeFileName() throws {
    let take = RecordingTake(
        name: "  /private:take  ",
        events: [
            RecordingTakeEvent(time: 0, kind: .noteOn(midi: 60, velocity: 200)),
            RecordingTakeEvent(time: 0.5, kind: .noteOff(midi: 60)),
        ]
    )

    let schedule = RecordingTakeSequenceAdapter().makeMIDISchedule(from: take)
    let export = try RecordingMIDIExportService().makeMIDIExport(from: take)

    #expect(schedule.first?.kind == .noteOn(midi: 60, velocity: 127))
    #expect(export.data.isEmpty == false)
    #expect(export.fileName == "-private-take.mid")
}

@Test @MainActor func stoppingTakePlaybackInvalidatesSuspendedPlayBeforeLoad() async throws {
    let playback = SuspendingTakePlaybackService()
    let controller = TakePlaybackController(playbackService: playback)
    let take = RecordingTake(
        name: "Race",
        events: [
            RecordingTakeEvent(time: 0, kind: .noteOn(midi: 60, velocity: 90)),
            RecordingTakeEvent(time: 0.1, kind: .noteOff(midi: 60)),
        ]
    )

    let playTask = Task { try await controller.play(take: take) }
    await playback.waitForFirstStop()
    let stopTask = Task { await controller.stop() }
    await playback.waitForStopCount(2)
    await playback.resumeFirstStop()
    try await playTask.value
    await stopTask.value

    #expect(await playback.loadCount == 0)
    #expect(await playback.playCount == 0)
    #expect(controller.isPlaying == false)
}

private func midiObservation(
    at seconds: TimeInterval,
    event: PerformanceObservation.Event
) -> PerformanceObservation {
    let instant = PerformanceMonotonicInstant(seconds: seconds)
    return PerformanceObservation(
        source: .init(kind: .midi1, id: "endpoint:42", generation: 1),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: event,
        channel: 1,
        group: 0
    )
}

private func targetAudioObservation(at seconds: TimeInterval) -> PerformanceObservation {
    let instant = PerformanceMonotonicInstant(seconds: seconds)
    return PerformanceObservation(
        source: .init(kind: .targetAudio, id: "audio:target", generation: 1),
        timing: .init(
            host: instant,
            source: nil,
            correctedHost: instant,
            mapping: nil,
            provenance: .hostOnly
        ),
        event: .targetAudioDetection(
            targetMIDINotes: [60],
            detectedMIDINotes: [60],
            result: .detected
        )
    )
}

private func makeTakeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "RecordingTakeCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private final class TakeDocumentsFileManager: FileManager {
    private let documentsURL: URL

    init(documentsURL: URL) {
        self.documentsURL = documentsURL
        super.init()
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        directory == .documentDirectory ? [documentsURL] : super.urls(for: directory, in: domainMask)
    }
}

private actor SuspendingTakePlaybackService: PracticeSequencerPlaybackServiceProtocol {
    private var stopCount = 0
    private var firstStopContinuation: CheckedContinuation<Void, Never>?
    private(set) var loadCount = 0
    private(set) var playCount = 0

    func warmUp() async throws {}

    func stop(resetCommands _: [PerformanceTransportCommand]) async {
        stopCount += 1
        guard stopCount == 1 else { return }
        await withCheckedContinuation { continuation in
            firstStopContinuation = continuation
        }
    }

    func load(sequence _: PracticeSequencerSequence) async throws { loadCount += 1 }
    func play(fromSeconds _: TimeInterval) async throws { playCount += 1 }
    func currentSeconds() async -> TimeInterval { 0 }
    func playOneShot(commands _: [PracticePlaybackCommand], durationSeconds _: TimeInterval) async throws {}
    func execute(commands _: [PracticePlaybackCommand]) async throws {}
    func stopAllLiveNotes() async {}

    func waitForFirstStop() async {
        while stopCount == 0 { await Task.yield() }
    }

    func waitForStopCount(_ expectedCount: Int) async {
        while stopCount < expectedCount { await Task.yield() }
    }

    func resumeFirstStop() {
        firstStopContinuation?.resume()
        firstStopContinuation = nil
    }
}
