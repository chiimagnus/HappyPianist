import SwiftUI
import UniformTypeIdentifiers

struct TakeLibraryView: View {
    let takes: [RecordingTake]
    @Bindable var playbackViewModel: TakePlaybackViewModel
    var isRecording: Bool = false
    var errorMessage: String?
    let alignmentDiagnostics: [UUID: RecordedTakeAlignmentDiagnostics]
    let onErrorDismiss: () -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onClearAll: () -> Void
    let makeMIDIExport: (RecordingTake) throws -> RecordingMIDIExport

    private let presentationViewModel: TakeLibraryPresentationViewModel

    @State private var renameTarget: RecordingTake?
    @State private var renameText = ""
    @State private var isRenamePresented = false
    @State private var exportDocument: MIDIFileDocument?
    @State private var exportFileName: String = ""
    @State private var isMIDIExportPresented = false
    @State private var presentedErrorMessage = ""
    @State private var isErrorPresented = false
    @State private var isClearAllConfirmationPresented = false

    init(
        takes: [RecordingTake],
        playbackViewModel: TakePlaybackViewModel,
        isRecording: Bool = false,
        errorMessage: String? = nil,
        alignmentDiagnostics: [UUID: RecordedTakeAlignmentDiagnostics] = [:],
        onErrorDismiss: @escaping () -> Void,
        onRename: @escaping (UUID, String) -> Void,
        onDelete: @escaping (UUID) -> Void,
        onClearAll: @escaping () -> Void,
        makeMIDIExport: @escaping (RecordingTake) throws -> RecordingMIDIExport,
        presentationViewModel: TakeLibraryPresentationViewModel = TakeLibraryPresentationViewModel()
    ) {
        self.takes = takes
        self.playbackViewModel = playbackViewModel
        self.isRecording = isRecording
        self.errorMessage = errorMessage
        self.alignmentDiagnostics = alignmentDiagnostics
        self.onErrorDismiss = onErrorDismiss
        self.onRename = onRename
        self.onDelete = onDelete
        self.onClearAll = onClearAll
        self.makeMIDIExport = makeMIDIExport
        self.presentationViewModel = presentationViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            if takes.isEmpty {
                ContentUnavailableView(
                    "没有录制",
                    systemImage: "mic.slash",
                    description: Text("在练习时点击录制按钮开始录制。")
                )
            } else {
                List {
                    ForEach(takes) { take in
                        TakeLibraryRowView(
                            take: take,
                            metadataText: presentationViewModel.metadataText(
                                for: take,
                                alignment: alignmentDiagnostics[take.id]
                            ),
                            isPlaying: playbackViewModel.isPlaying(takeID: take.id),
                            isDisabled: isRecording,
                            onPlayPause: { playOrPause(take) },
                            onRename: { beginRenaming(take) },
                            onExport: { exportMIDI(take) },
                            onDelete: { onDelete(take.id) }
                        )
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            TakeNowPlayingBarView(
                playbackViewModel: playbackViewModel,
                isRecording: isRecording,
                totalDuration: totalDuration,
                presentationViewModel: presentationViewModel,
                onTogglePlayback: toggleCurrentPlayback,
                onStopPlayback: { Task { await playbackViewModel.stop() } },
                onCommitScrubbing: commitScrubbing
            )
        }
        .onAppear {
            playbackViewModel.startProgressUpdates()
            presentExternalErrorIfNeeded()
        }
        .onDisappear {
            playbackViewModel.stopProgressUpdates()
        }
        .onChange(of: errorMessage) {
            presentExternalErrorIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("清空全部录制", systemImage: "trash", role: .destructive) {
                        isClearAllConfirmationPresented = true
                    }
                    .disabled(takes.isEmpty)
                } label: {
                    Label("更多录制操作", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .disabled(isRecording)
            }
        }
        .confirmationDialog(
            "清空全部录制？",
            isPresented: $isClearAllConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                Task { await playbackViewModel.stop() }
                onClearAll()
            }
        } message: {
            Text("此操作会删除所有录制，且不可恢复。")
        }
        .fileExporter(
            isPresented: $isMIDIExportPresented,
            document: exportDocument,
            contentType: .midi,
            defaultFilename: exportFileName
        ) { _ in
            exportDocument = nil
        }
        .alert("错误", isPresented: $isErrorPresented) {
            Button("知道了", action: dismissPresentedError)
        } message: {
            Text(presentedErrorMessage)
        }
        .alert("重命名", isPresented: $isRenamePresented) {
            TextField("名称", text: $renameText)
            Button("确定", action: confirmRename)
            Button("取消", role: .cancel, action: cancelRename)
        }
    }

    private var totalDuration: TimeInterval {
        guard playbackViewModel.currentTakeID != nil else { return 0 }
        return playbackViewModel.currentDurationSeconds
    }

    private func beginRenaming(_ take: RecordingTake) {
        renameText = take.name
        renameTarget = take
        isRenamePresented = true
    }

    private func confirmRename() {
        if let target = renameTarget, renameText.isEmpty == false {
            onRename(target.id, renameText)
        }
        cancelRename()
    }

    private func cancelRename() {
        renameTarget = nil
        renameText = ""
        isRenamePresented = false
    }

    private func playOrPause(_ take: RecordingTake) {
        Task {
            do {
                try await playbackViewModel.playOrPause(take: take)
            } catch {
                presentError("播放失败：\(error.localizedDescription)")
            }
        }
    }

    private func toggleCurrentPlayback() {
        Task {
            do {
                try await playbackViewModel.toggleCurrentPlayback()
            } catch {
                presentError("播放失败：\(error.localizedDescription)")
            }
        }
    }

    private func commitScrubbing() {
        Task {
            do {
                try await playbackViewModel.commitScrubbing()
            } catch {
                presentError("定位播放位置失败：\(error.localizedDescription)")
            }
        }
    }

    private func exportMIDI(_ take: RecordingTake) {
        do {
            let export = try makeMIDIExport(take)
            exportDocument = MIDIFileDocument(data: export.data)
            exportFileName = export.fileName
            isMIDIExportPresented = true
        } catch {
            presentError("导出失败：\(error.localizedDescription)")
        }
    }

    private func presentExternalErrorIfNeeded() {
        guard let errorMessage else { return }
        presentError(errorMessage)
    }

    private func presentError(_ message: String) {
        presentedErrorMessage = message
        isErrorPresented = true
    }

    private func dismissPresentedError() {
        isErrorPresented = false
        presentedErrorMessage = ""
        onErrorDismiss()
    }
}
