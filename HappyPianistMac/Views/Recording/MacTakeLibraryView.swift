import Foundation
import Observation
import Practice
import SwiftUI
import UniformTypeIdentifiers

struct MacTakeLibraryView: View {
    @Bindable var takeLibraryViewModel: TakeLibraryViewModel
    @Bindable var takePlaybackViewModel: TakePlaybackViewModel
    let isRecording: Bool
    let canPlayTakes: Bool
    let errorMessage: String?
    let dismissError: () -> Void
    let playOrPause: @MainActor (RecordingTake) async -> Void
    let togglePlayback: @MainActor () async -> Void
    let stopPlayback: @MainActor () async -> Void
    let seek: @MainActor (TimeInterval) async -> Void
    let rename: (RecordingTake, String) -> Void
    let delete: @MainActor (RecordingTake) async -> Void
    let clearAll: @MainActor () async -> Void
    let makeMIDIExport: (RecordingTake) -> RecordingMIDIExport?

    @State private var renameTarget: RecordingTake?
    @State private var renameText = ""
    @State private var isRenamePresented = false
    @State private var isClearAllConfirmationPresented = false
    @State private var exportDocument: MacMIDIFileDocument?
    @State private var exportFileName = ""
    @State private var isMIDIExportPresented = false
    @State private var presentedErrorMessage = ""
    @State private var isErrorPresented = false

    var body: some View {
        VStack(spacing: 0) {
            if takeLibraryViewModel.takes.isEmpty {
                ContentUnavailableView(
                    "没有 MIDI 录制",
                    systemImage: "pianokeys",
                    description: Text("在练习时开始录制，即可在这里回放或导出。")
                )
            } else {
                List(takeLibraryViewModel.takes) { take in
                    takeRow(take)
                }
                .scrollIndicators(.hidden)
            }

            Divider()
            playbackControls
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            takePlaybackViewModel.startProgressUpdates()
            presentExternalErrorIfNeeded()
        }
        .onDisappear {
            takePlaybackViewModel.stopProgressUpdates()
        }
        .onChange(of: errorMessage) {
            presentExternalErrorIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清空全部录制", systemImage: "trash", role: .destructive) {
                    isClearAllConfirmationPresented = true
                }
                .disabled(takeLibraryViewModel.takes.isEmpty || isRecording)
            }
        }
        .confirmationDialog(
            "清空全部录制？",
            isPresented: $isClearAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                Task { await clearAll() }
            }
        } message: {
            Text("此操作会删除所有录制，且不可恢复。")
        }
        .alert("重命名录制", isPresented: $isRenamePresented) {
            TextField("名称", text: $renameText)
            Button("确定", action: confirmRename)
            Button("取消", role: .cancel, action: cancelRename)
        }
        .alert("录制操作失败", isPresented: $isErrorPresented) {
            Button("知道了", action: dismissPresentedError)
        } message: {
            Text(presentedErrorMessage)
        }
        .fileExporter(
            isPresented: $isMIDIExportPresented,
            document: exportDocument,
            contentType: .midi,
            defaultFilename: exportFileName
        ) { _ in
            exportDocument = nil
        }
    }

    private func takeRow(_ take: RecordingTake) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(take.name)
                    .font(.headline)
                Text("\(formattedDuration(take.durationSeconds)) · \(take.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                takePlaybackViewModel.isPlaying(takeID: take.id) ? "暂停录制回放" : "播放录制",
                systemImage: takePlaybackViewModel.isPlaying(takeID: take.id) ? "pause.fill" : "play.fill"
            ) {
                Task { await playOrPause(take) }
            }
            .disabled(isRecording || canPlayTakes == false || take.events.isEmpty)

            Menu {
                Button("重命名", systemImage: "pencil") {
                    beginRenaming(take)
                }
                .disabled(isRecording)

                Button("导出 MIDI...", systemImage: "square.and.arrow.up") {
                    exportMIDI(take)
                }

                Button("删除", systemImage: "trash", role: .destructive) {
                    Task { await delete(take) }
                }
                .disabled(isRecording)
            } label: {
                Label("更多录制操作", systemImage: "ellipsis.circle")
            }
        }
        .padding(.vertical, 4)
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button(
                takePlaybackViewModel.isPlaying ? "暂停回放" : "继续回放",
                systemImage: takePlaybackViewModel.isPlaying ? "pause.fill" : "play.fill"
            ) {
                Task { await togglePlayback() }
            }
            .disabled(playbackControlsAreUnavailable)

            Button("停止回放", systemImage: "stop.fill") {
                Task { await stopPlayback() }
            }
            .disabled(playbackControlsAreUnavailable)

            Slider(
                value: $takePlaybackViewModel.scrubPositionSeconds,
                in: 0 ... max(0.001, takePlaybackViewModel.currentDurationSeconds)
            ) { editing in
                if editing {
                    takePlaybackViewModel.beginScrubbing()
                } else {
                    Task { await seek(takePlaybackViewModel.scrubPositionSeconds) }
                }
            }
            .disabled(playbackControlsAreUnavailable)

            Text(formattedDuration(takePlaybackViewModel.displayedPositionSeconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("/ \(formattedDuration(takePlaybackViewModel.currentDurationSeconds))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding()
    }

    private var playbackControlsAreUnavailable: Bool {
        isRecording || canPlayTakes == false || takePlaybackViewModel.currentTakeID == nil
    }

    private func beginRenaming(_ take: RecordingTake) {
        renameTarget = take
        renameText = take.name
        isRenamePresented = true
    }

    private func confirmRename() {
        if let renameTarget {
            rename(renameTarget, renameText)
        }
        cancelRename()
    }

    private func cancelRename() {
        renameTarget = nil
        renameText = ""
        isRenamePresented = false
    }

    private func exportMIDI(_ take: RecordingTake) {
        guard let export = makeMIDIExport(take) else { return }
        exportDocument = MacMIDIFileDocument(data: export.data)
        exportFileName = export.fileName
        isMIDIExportPresented = true
    }

    private func presentExternalErrorIfNeeded() {
        guard let errorMessage else { return }
        presentedErrorMessage = errorMessage
        isErrorPresented = true
    }

    private func dismissPresentedError() {
        isErrorPresented = false
        presentedErrorMessage = ""
        dismissError()
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let clampedSeconds = max(0, Int(seconds))
        let minutes = clampedSeconds / 60
        let remainingSeconds = clampedSeconds % 60
        return "\(minutes):\(remainingSeconds.formatted(.number.precision(.integerLength(2))))"
    }
}
