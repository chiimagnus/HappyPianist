import SwiftUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
  @Bindable var viewModel: SongLibraryViewModel
  @Bindable var diagnosticsViewModel: DiagnosticsViewModel
  let onBackToPreparation: @MainActor () -> Void
  let onStartPractice: @MainActor (UUID) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isAudioImporterPresented = false
  @State private var pendingAudioBindingEntryID: UUID?
  @State private var pendingDeletionEntryID: UUID?
  @State private var pendingImportConfirmationID: UUID?
  @State private var isDiagnosticsPresented = false
  @State private var libraryViewHeight = LibraryDesignTokens.windowIdealHeight

  private var audioImporterTypes: [UTType] {
    let types = SongLibraryViewModel.supportedAudioFileExtensions.compactMap {
      UTType(filenameExtension: $0)
    }
    return types.isEmpty ? [.audio] : types
  }

  var body: some View {
    let entries = viewModel.entries
    let selectedIndex = entries.firstIndex(where: { $0.id == viewModel.selectedEntryID })
    let selectedEntry = selectedIndex.map { entries[$0] }
    let selectedPresentation = selectedIndex.map {
      SongLibraryTrackPresentation(entry: entries[$0], index: $0)
    }
    let selectedIsPlaying =
      selectedEntry.map { viewModel.isListeningPlaying(entryID: $0.id) } ?? false
    let selectedDuration = resolvedDuration(
      presentation: selectedPresentation, selectedEntry: selectedEntry)
    let selectedCurrentTime = resolvedCurrentTime(selectedEntry: selectedEntry)
    let selectedProgress = selectedDuration > 0 ? selectedCurrentTime / selectedDuration : 0
    let requiresAudioImport =
      selectedEntry != nil && selectedEntry?.audioFileName == nil
      && selectedEntry?.isBundled != true
    let canPerformPlaybackAction = selectedEntry?.audioFileName != nil || requiresAudioImport

    VStack(spacing: 0) {
      LibraryTopBarView(
        onBack: onBackToPreparation,
        onDiagnostics: { isDiagnosticsPresented = true }
      )

      if viewModel.isLibraryLoading
        || (viewModel.hasLoadedLibrary == false && viewModel.bootstrapFailureMessage == nil)
      {
        ProgressView("正在加载乐曲库…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let bootstrapFailureMessage = viewModel.bootstrapFailureMessage {
        ContentUnavailableView {
          Label("无法加载乐曲库", systemImage: "exclamationmark.triangle")
        } description: {
          Text(bootstrapFailureMessage)
        } actions: {
          Button("重试", systemImage: "arrow.clockwise") {
            Task { @MainActor in
              await viewModel.loadLibraryIfNeeded()
            }
          }
          .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if entries.isEmpty {
        SongLibraryEmptyView(onImport: viewModel.didTapImportMusicXML)
      } else if let selectedEntry, let selectedPresentation {
        ZStack(alignment: .bottomTrailing) {
          VStack(spacing: 0) {
            LibraryCrateView(
              entries: entries,
              selectedEntryID: viewModel.selectedEntryID,
              playingEntryID: viewModel.currentListeningEntryID,
              isPlaying: selectedIsPlaying,
              reduceMotion: reduceMotion,
              allowsDestructiveActions: viewModel.importState.isActive == false,
              onSelectEntry: viewModel.selectEntry,
              onTogglePlayback: togglePlayback,
              onImportMusicXML: viewModel.didTapImportMusicXML,
              onBindAudio: presentAudioImporter,
              onDelete: requestDeletion
            )

            LibraryTrackInfoView(
              presentation: selectedPresentation,
              progress: selectedProgress,
              currentTime: selectedCurrentTime,
              duration: selectedDuration,
              canSeek: viewModel.currentListeningEntryID == selectedEntry.id && selectedDuration > 0,
              playbackTitle: playbackButtonTitle(
                requiresAudioImport: requiresAudioImport,
                isPlaying: selectedIsPlaying
              ),
              playbackSystemImage: playbackButtonSystemImage(
                requiresAudioImport: requiresAudioImport,
                isPlaying: selectedIsPlaying
              ),
              canPerformPlaybackAction: canPerformPlaybackAction,
              onPlayback: toggleSelectedPlayback,
              onSeek: { progress in
                viewModel.seekListening(entryID: selectedEntry.id, progress: progress)
              }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.bottom, 22)
          }

          Button("开始练习", systemImage: "music.note") {
            viewModel.startPractice(entryID: selectedEntry.id, perform: onStartPractice)
          }
          .buttonStyle(.borderedProminent)
          .disabled(viewModel.importState.isActive)
          .accessibilityHint(
            viewModel.importState.isActive
              ? "曲谱导入完成或取消后才能开始练习"
              : "在练习窗口中准备并打开当前曲目"
          )
          .padding()
        }
      }
    }
    .frame(
      minWidth: 780,
      idealWidth: 1140,
      maxWidth: 1240,
      minHeight: LibraryDesignTokens.windowMinimumHeight,
      idealHeight: LibraryDesignTokens.windowIdealHeight,
      maxHeight: LibraryDesignTokens.windowMaximumHeight
    )
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
      libraryViewHeight = height
    }
    .safeAreaInset(edge: .top) {
      if viewModel.importState.isActive {
        LibraryImportStatusView(
          state: viewModel.importState,
          onReviewConflict: { operationID in
            pendingImportConfirmationID = operationID
          },
          onCancelCurrent: { operationID in
            Task { @MainActor in
              await viewModel.cancelPendingImport(operationID: operationID)
            }
          },
          onContinue: {
            Task { @MainActor in
              await viewModel.continueAfterImportFailure()
            }
          },
          onCancelAll: {
            Task { @MainActor in
              await viewModel.cancelAllImports()
            }
          }
        )
        .padding(.horizontal)
      }
    }
    .ornament(
      attachmentAnchor: .scene(.trailing),
      contentAlignment: .leading
    ) {
      LibraryPracticeProgressOrnamentView(state: viewModel.practiceSnapshotState)
        .frame(width: 400, height: libraryViewHeight)
        .glassBackgroundEffect()
    }
    .sheet(isPresented: $isDiagnosticsPresented) {
      DiagnosticsView(viewModel: diagnosticsViewModel)
    }
    .fileImporter(
      isPresented: $isAudioImporterPresented,
      allowedContentTypes: audioImporterTypes,
      allowsMultipleSelection: false,
      onCompletion: handleAudioImport
    )
    .task {
      await viewModel.loadLibraryIfNeeded()
    }
    .onDisappear {
      viewModel.stopListening()
      Task { @MainActor in
        await viewModel.cancelAllImports()
        await viewModel.flushPendingSelectionPersistence()
      }
    }
    .onChange(of: viewModel.importState) { _, state in
      guard case let .awaitingConfirmation(pending, _, _) = state else {
        pendingImportConfirmationID = nil
        return
      }
      pendingImportConfirmationID = pending.id
    }
    .alert(
      "提示",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil },
        set: { isPresented in
          if isPresented == false {
            viewModel.dismissError()
          }
        }
      )
    ) {
      Button("好", action: viewModel.dismissError)
    } message: {
      Text(viewModel.errorMessage ?? "未知错误")
    }
    .confirmationDialog(
      importConflictTitle,
      isPresented: Binding(
        get: { pendingImportConfirmationID != nil && pendingImport != nil },
        set: { isPresented in
          if isPresented == false {
            pendingImportConfirmationID = nil
          }
        }
      ),
      titleVisibility: .visible
    ) {
      if let pendingImport {
        let presentation = SongLibraryImportConflictPresentation(conflict: pendingImport.conflict)
        if let actionTitle = presentation.actionTitle {
          Button(actionTitle, role: presentation.actionRole) {
            pendingImportConfirmationID = nil
            Task { @MainActor in
              await viewModel.confirmPendingImport(operationID: pendingImport.id)
            }
          }
        }
      }
      if let pendingImport {
        Button("跳过此项", role: .cancel) {
          pendingImportConfirmationID = nil
          Task { @MainActor in
            await viewModel.cancelPendingImport(operationID: pendingImport.id)
          }
        }
      }
    } message: {
      Text(importConflictPresentation?.message ?? "曲谱冲突状态已变化。")
    }
    .confirmationDialog(
      "确认删除该曲目？",
      isPresented: Binding(
        get: { pendingDeletionEntryID != nil },
        set: { isPresented in
          if isPresented == false {
            pendingDeletionEntryID = nil
          }
        }
      )
    ) {
      Button("删除", role: .destructive, action: deletePendingEntry)
      Button("取消", role: .cancel) {
        pendingDeletionEntryID = nil
      }
    } message: {
      Text("删除后将移除曲谱文件及已绑定音频文件，且无法撤销。")
    }
  }

  private func resolvedDuration(
    presentation: SongLibraryTrackPresentation?,
    selectedEntry: SongLibraryEntry?
  ) -> TimeInterval {
    if let selectedEntry,
      viewModel.currentListeningEntryID == selectedEntry.id,
      viewModel.listeningDuration > 0
    {
      return viewModel.listeningDuration
    }
    return presentation?.knownDuration ?? 0
  }

  private var pendingImport: SongLibraryPendingImport? {
    guard case let .awaitingConfirmation(pending, _, _) = viewModel.importState,
      pending.id == pendingImportConfirmationID
    else { return nil }
    return pending
  }

  private var importConflictTitle: String {
    guard let pendingImport else { return "处理曲谱冲突" }
    return "处理“\(pendingImport.fileName)”"
  }

  private var importConflictPresentation: SongLibraryImportConflictPresentation? {
    pendingImport.map { SongLibraryImportConflictPresentation(conflict: $0.conflict) }
  }

  private func resolvedCurrentTime(selectedEntry: SongLibraryEntry?) -> TimeInterval {
    guard let selectedEntry, viewModel.currentListeningEntryID == selectedEntry.id else { return 0 }
    return viewModel.listeningCurrentTime
  }

  private func playbackButtonTitle(requiresAudioImport: Bool, isPlaying: Bool) -> String {
    if requiresAudioImport {
      return "导入音频"
    }
    return isPlaying ? "暂停" : "播放"
  }

  private func playbackButtonSystemImage(requiresAudioImport: Bool, isPlaying: Bool) -> String {
    if requiresAudioImport {
      return "waveform.badge.plus"
    }
    return isPlaying ? "pause.fill" : "play.fill"
  }

  private func toggleSelectedPlayback() {
    guard let selectedEntryID = viewModel.selectedEntryID else { return }
    togglePlayback(selectedEntryID)
  }

  private func togglePlayback(_ entryID: UUID) {
    guard let entry = viewModel.entries.first(where: { $0.id == entryID }) else { return }
    guard entry.audioFileName != nil else {
      if entry.isBundled == true {
        viewModel.errorMessage = "此内置曲目没有可播放的音频。"
      } else {
        presentAudioImporter(entryID)
      }
      return
    }
    Task { @MainActor in
      await viewModel.didTapListen(entryID: entryID)
    }
  }

  private func presentAudioImporter(_ entryID: UUID) {
    guard let entry = viewModel.entries.first(where: { $0.id == entryID }), entry.isBundled != true
    else {
      return
    }
    pendingAudioBindingEntryID = entryID
    isAudioImporterPresented = true
  }

  private func requestDeletion(_ entryID: UUID) {
    guard viewModel.importState.isActive == false else {
      viewModel.errorMessage = "曲谱导入完成或取消后才能删除曲目。"
      return
    }
    guard let entry = viewModel.entries.first(where: { $0.id == entryID }), entry.isBundled != true
    else {
      return
    }
    pendingDeletionEntryID = entryID
  }

  private func handleAudioImport(_ result: Result<[URL], Error>) {
    defer { pendingAudioBindingEntryID = nil }

    do {
      let urls = try result.get()
      guard let entryID = pendingAudioBindingEntryID, let audioURL = urls.first else { return }
      Task { @MainActor in
        await viewModel.bindAudio(entryID: entryID, from: audioURL)
      }
    } catch {
      viewModel.errorMessage = "导入音频失败：\(error.localizedDescription)"
    }
  }

  private func deletePendingEntry() {
    guard let entryID = pendingDeletionEntryID else { return }
    Task { @MainActor in
      await viewModel.deleteEntry(entryID: entryID)
      pendingDeletionEntryID = nil
    }
  }
}

private struct LibraryImportStatusView: View {
  let state: SongLibraryImportState
  let onReviewConflict: (UUID) -> Void
  let onCancelCurrent: (UUID) -> Void
  let onContinue: () -> Void
  let onCancelAll: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if showsProgress {
        ProgressView()
          .controlSize(.small)
      }

      Text(statusText)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)

      switch state {
      case let .awaitingConfirmation(pending, _, _):
        Button("处理此项") { onReviewConflict(pending.id) }
          .buttonStyle(.borderedProminent)
        Button("取消此项") { onCancelCurrent(pending.id) }
          .buttonStyle(.bordered)
        Button("取消剩余导入", role: .cancel, action: onCancelAll)
          .buttonStyle(.bordered)
      case .itemFailure:
        Button("继续下一项", action: onContinue)
          .buttonStyle(.borderedProminent)
        Button("取消剩余导入", role: .cancel, action: onCancelAll)
          .buttonStyle(.bordered)
      case .staging, .processing:
        Button("取消导入", role: .cancel, action: onCancelAll)
          .buttonStyle(.bordered)
      case .idle:
        EmptyView()
      }
    }
    .padding(12)
    .background(.regularMaterial, in: .rect(cornerRadius: 14))
    .accessibilityElement(children: .contain)
  }

  private var showsProgress: Bool {
    switch state {
    case .staging, .processing:
      true
    case .idle, .awaitingConfirmation, .itemFailure:
      false
    }
  }

  private var statusText: String {
    switch state {
    case let .staging(index, count):
      "正在暂存曲谱 \(min(index + 1, count))/\(count)…"
    case let .processing(_, index, count):
      "正在导入第 \(index)/\(count) 项…"
    case let .awaitingConfirmation(pending, index, count):
      "第 \(index)/\(count) 项“\(pending.fileName)”需要确认后才能继续。"
    case let .itemFailure(failure, index, count):
      "第 \(index)/\(count) 项“\(failure.fileName)”失败：\(failure.message)"
    case .idle:
      ""
    }
  }
}

#Preview {
  let graph = LiveAppGraph.make()
  SongLibraryView(
    viewModel: graph.songLibraryViewModel,
    diagnosticsViewModel: graph.diagnosticsViewModel,
    onBackToPreparation: {},
    onStartPractice: { _ in }
  )

}

struct SongLibraryImportConflictPresentation {
  let actionTitle: String?
  let actionRole: ButtonRole?
  let message: String

  init(conflict: SongLibraryImportConflictKind) {
    switch conflict {
    case .indexedTarget:
      actionTitle = "替换现有曲谱"
      actionRole = .destructive
      message = "将替换现有曲谱文件并保留曲目名称、音频、练习历史和曲库位置。"
    case .indexedMissingTarget:
      actionTitle = "修复缺失曲谱"
      actionRole = nil
      message = "曲库条目仍在，但曲谱文件缺失。将用所选文件修复该曲目。"
    case .filesystemOrphan:
      actionTitle = "替换并加入曲库"
      actionRole = .destructive
      message = "同名文件尚未加入曲库。将替换该文件并创建新的曲库条目。"
    case .none:
      actionTitle = "继续导入"
      actionRole = nil
      message = "冲突已消失，将按新曲谱导入。"
    case .ambiguousIndexedTargets:
      actionTitle = nil
      actionRole = nil
      message = "多个曲库条目指向同一文件，无法安全判断要更新哪一项。"
    }
  }
}

private struct LibraryTopBarView: View {
  let onBack: () -> Void
  let onDiagnostics: () -> Void

  var body: some View {
    HStack {
      Button("重新选择钢琴", action: onBack)
        .buttonStyle(.bordered)

      Spacer()

      Button("诊断", systemImage: "stethoscope", action: onDiagnostics)
        .buttonStyle(.bordered)
    }
    .frame(height: 70)
    .padding(.horizontal, 28)
  }
}

private struct SongLibraryEmptyView: View {
  let onImport: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("乐曲库为空", systemImage: "record.circle")
        .foregroundStyle(LibraryDesignTokens.text)
    } description: {
      Text("导入 MusicXML 后，曲谱会以黑胶唱片的形式出现在这里。")
        .foregroundStyle(LibraryDesignTokens.secondaryText)
    } actions: {
      Button("导入 MusicXML", systemImage: "plus", action: onImport)
        .buttonStyle(.borderedProminent)
        .tint(LibraryDesignTokens.accent)
        .foregroundStyle(LibraryDesignTokens.accentForeground)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct LibraryTrackInfoView: View {
  let presentation: SongLibraryTrackPresentation
  let progress: Double
  let currentTime: TimeInterval
  let duration: TimeInterval
  let canSeek: Bool
  let playbackTitle: String
  let playbackSystemImage: String
  let canPerformPlaybackAction: Bool
  let onPlayback: () -> Void
  let onSeek: (Double) -> Void

  @State private var progressBarWidth: CGFloat = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(presentation.title)
        .font(.system(.largeTitle, design: .serif))
        .bold()
        .foregroundStyle(LibraryDesignTokens.text)
        .lineLimit(1)
        .minimumScaleFactor(0.72)

      Text(presentation.subtitle)
        .font(.subheadline)
        .foregroundStyle(LibraryDesignTokens.secondaryText)
        .lineLimit(1)

      HStack(alignment: .bottom, spacing: 14) {
        VStack(spacing: 7) {
          ZStack(alignment: .leading) {
            Capsule()
              .fill(LibraryDesignTokens.line)

            Capsule()
              .fill(LibraryDesignTokens.text)
              .frame(width: progressBarWidth * min(max(progress, 0), 1))
          }
          .frame(height: 5)
          .contentShape(.rect)
          .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            progressBarWidth = width
          }
          .gesture(
            SpatialTapGesture()
              .onEnded { value in
                guard canSeek, progressBarWidth > 0 else { return }
                onSeek(min(max(value.location.x / progressBarWidth, 0), 1))
              }
          )
          .accessibilityLabel("播放进度")
          .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
          .accessibilityAdjustableAction { direction in
            guard canSeek else { return }
            let currentProgress = min(max(progress, 0), 1)
            switch direction {
            case .increment:
              onSeek(min(currentProgress + 0.05, 1))
            case .decrement:
              onSeek(max(currentProgress - 0.05, 0))
            @unknown default:
              break
            }
          }

          HStack {
            Text(Self.formattedTime(currentTime))
            Spacer()
            Text(Self.formattedTime(duration))
          }
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(LibraryDesignTokens.faintText)
        }
        .frame(maxWidth: 340)

        Button(playbackTitle, systemImage: playbackSystemImage, action: onPlayback)
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .disabled(canPerformPlaybackAction == false)
      }
      .padding(.top, 9)
    }
  }

  private static func formattedTime(_ time: TimeInterval) -> String {
    guard time.isFinite, time > 0 else { return "0:00" }
    let totalSeconds = Int(time.rounded(.down))
    let seconds = totalSeconds % 60
    let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
    return "\(totalSeconds / 60):\(secondsText)"
  }
}
