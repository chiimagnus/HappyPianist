import Foundation
import MIDI
import Practice
@testable import HappyPianistMac
import Testing

@MainActor
struct MacRecordingWorkflowTests {
    @Test func recordingStopsOpenNotesAndReturnPersistsTheTake() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        await fixture.viewModel.startTakeRecording()
        fixture.input.yield(note: 60)
        #expect(await recordingSettles { fixture.viewModel.lastAttempt == .matched })

        #expect(await fixture.viewModel.stopTakeRecording())
        let take = try #require(fixture.viewModel.takeLibraryViewModel.takes.first)
        #expect(take.events.contains { if case .noteOn(midi: 60, velocity: 96) = $0.kind { true } else { false } })
        #expect(take.events.contains { if case .noteOff(midi: 60) = $0.kind { true } else { false } })
        #expect(take.metadata.scoreIdentity != nil)
        #expect(take.metadata.inputSources.contains { $0.kind != nil })
        #expect(take.metadata.inputSources.contains { $0.id.contains(fixture.temporaryRoot.path()) } == false)

        #expect(await fixture.viewModel.returnToLibrary())
        #expect(fixture.takeStore.takes == [take])
    }

    @Test func takeLibrarySupportsRenameExportPlaybackDeleteAndClear() async throws {
        let fixture = try MacPracticeFixture(hasSelectedOutput: true)
        defer { fixture.removeTemporaryRoot() }

        let firstTake = try await recordTake(with: fixture, note: 60)
        fixture.viewModel.renameTake(firstTake, to: "回放测试")
        let renamedTake = try #require(fixture.viewModel.takeLibraryViewModel.takes.first)
        #expect(renamedTake.name == "回放测试")

        let export = try #require(fixture.viewModel.makeMIDIExport(for: renamedTake))
        #expect(export.fileName == "回放测试.mid")
        #expect(export.data.isEmpty == false)

        await fixture.viewModel.playOrPauseTake(renamedTake)
        #expect(fixture.referencePlayback.playCount == 1)
        #expect(fixture.viewModel.takePlaybackViewModel.currentTakeID == renamedTake.id)

        await fixture.viewModel.seekTakePlayback(to: 0)
        #expect(fixture.referencePlayback.playCount == 2)

        await fixture.viewModel.deleteTake(renamedTake)
        #expect(fixture.viewModel.takeLibraryViewModel.takes.isEmpty)
        #expect(fixture.referencePlayback.stopCount > 0)

        _ = fixture.viewModel.takeLibraryViewModel.addTake(firstTake)
        await fixture.viewModel.clearAllTakes()
        #expect(fixture.viewModel.takeLibraryViewModel.takes.isEmpty)
        #expect(fixture.takeStore.takes.isEmpty)
    }

    @Test func missingOutputStillAllowsRecordingAndExportButNotPlayback() async throws {
        let fixture = try MacPracticeFixture()
        defer { fixture.removeTemporaryRoot() }

        let take = try await recordTake(with: fixture, note: 60)
        #expect(fixture.viewModel.canPlayTakes == false)
        #expect(try #require(fixture.viewModel.makeMIDIExport(for: take)).data.isEmpty == false)

        await fixture.viewModel.playOrPauseTake(take)
        #expect(fixture.referencePlayback.playCount == 0)
        #expect(fixture.viewModel.errorMessage == "请选择可用的 MIDI 输出后再播放录制。")
    }

    @Test func inputLossAndTakeSaveFailureKeepTheTakeUntilItCanBeSaved() async throws {
        let failingStore = MacPracticeTakeStore()
        failingStore.isSaveFailing = true
        let fixture = try MacPracticeFixture(takeStore: failingStore)
        defer { fixture.removeTemporaryRoot() }

        await fixture.viewModel.load(songID: fixture.songID)
        await fixture.viewModel.startTakeRecording()
        fixture.input.yield(note: 61)
        #expect(await recordingSettles { fixture.viewModel.lastAttempt == .wrongNote })
        fixture.input.emit(.selectedEndpointUnavailable(7))

        #expect(await recordingSettles { fixture.viewModel.state == .saveFailed })
        #expect(fixture.viewModel.isRecordingTake == false)
        #expect(fixture.takeStore.takes.isEmpty)

        failingStore.isSaveFailing = false
        #expect(await fixture.viewModel.returnToLibrary())
        #expect(fixture.takeStore.takes.count == 1)
        #expect(fixture.viewModel.state == .idle)
    }

    private func recordTake(
        with fixture: MacPracticeFixture,
        note: Int
    ) async throws -> RecordingTake {
        await fixture.viewModel.load(songID: fixture.songID)
        await fixture.viewModel.startTakeRecording()
        fixture.input.yield(note: note)
        #expect(await recordingSettles { fixture.viewModel.lastAttempt == .matched })
        #expect(await fixture.viewModel.stopTakeRecording())
        return try #require(fixture.viewModel.takeLibraryViewModel.takes.first)
    }
}

@MainActor
private func recordingSettles(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0 ..< 100 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}
