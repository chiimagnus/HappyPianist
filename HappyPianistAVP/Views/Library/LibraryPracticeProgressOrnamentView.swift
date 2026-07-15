import SwiftUI

struct LibraryPracticeProgressOrnamentView: View {
  let state: SongPracticeLibraryPresentationState
  let height: CGFloat
  let onRetry: () -> Void
  let onConfirmedReset: () -> Void

  var body: some View {
    ScrollView {
      LibraryPracticeOrnamentContentView(
        state: state,
        onRetry: onRetry,
        onConfirmedReset: onConfirmedReset
      )
        .padding(LibraryPracticeOrnamentLayout.contentPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .scrollIndicators(.hidden)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("当前曲目练习概览")
    .frame(
      minWidth: LibraryPracticeOrnamentLayout.minimumWidth,
      idealWidth: LibraryPracticeOrnamentLayout.idealWidth,
      maxWidth: LibraryPracticeOrnamentLayout.maximumWidth,
      minHeight: height,
      idealHeight: height,
      maxHeight: height
    )
  }
}

private enum LibraryPracticeOrnamentLayout {
  static let minimumWidth: CGFloat = 360
  static let idealWidth: CGFloat = 420
  static let maximumWidth: CGFloat = 440
  static let contentPadding: CGFloat = 24
  static let cardCornerRadius: CGFloat = 22
}

private struct LibraryPracticeOrnamentContentView: View {
  let state: SongPracticeLibraryPresentationState
  let onRetry: () -> Void
  let onConfirmedReset: () -> Void

  var body: some View {
    switch state {
    case .loading:
      LibraryPracticeLoadingView()
    case .invitation:
      LibraryPracticeInvitationView()
    case .overview(let overview):
      LibraryPracticeOverviewView(overview: overview)
    case .unavailable(let unavailable):
      LibraryPracticeUnavailableView(
        unavailable: unavailable,
        onRetry: onRetry,
        onConfirmedReset: onConfirmedReset
      )
    }
  }
}

private struct LibraryPracticeLoadingView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        ProgressView()

        VStack(alignment: .leading, spacing: 4) {
          Text("正在读取练习记录")
            .font(.headline)
            .bold()
          Text("正在准备当前曲目的练习概览。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)

      ForEach(0..<3, id: \.self) { _ in
        LibraryPracticeLoadingPlaceholderView()
      }
    }
    .padding(.top, 4)
  }
}

private struct LibraryPracticeLoadingPlaceholderView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Capsule()
        .fill(.primary.opacity(0.16))
        .frame(width: 96, height: 10)
      Capsule()
        .fill(.primary.opacity(0.09))
        .frame(maxWidth: .infinity)
        .frame(height: 9)
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .libraryPracticeCardSurface(
      cornerRadius: LibraryPracticeOrnamentLayout.cardCornerRadius
    )
    .accessibilityHidden(true)
  }
}

private struct LibraryPracticeUnavailableView: View {
  let unavailable: SongPracticeLibraryUnavailable
  let onRetry: () -> Void
  let onConfirmedReset: () -> Void

  @State private var isResetConfirmationPresented = false

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("重试", systemImage: "arrow.clockwise", action: onRetry)
        .buttonStyle(.borderedProminent)

      if unavailable.recoveryOptions == .retryAndConfirmedBackupReset {
        Button("备份并重置", systemImage: "externaldrive.badge.xmark") {
          isResetConfirmationPresented = true
        }
      }
    }
    .foregroundStyle(.primary)
    .frame(maxWidth: .infinity, minHeight: 420)
    .confirmationDialog(
      "备份并重置练习记录？",
      isPresented: $isResetConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("备份并重置", role: .destructive, action: onConfirmedReset)
      Button("取消", role: .cancel) {}
    } message: {
      Text("仅在记录已确认损坏时使用。原文件会先备份，再创建空记录。")
    }
  }

  private var title: String {
    switch unavailable.reason {
    case .temporarilyUnavailable: "暂时无法读取练习记录"
    case .corrupted: "练习记录已损坏"
    }
  }

  private var message: String {
    switch unavailable.reason {
    case .temporarilyUnavailable:
      "你仍然可以试听曲目；请稍后重试读取练习记录。"
    case .corrupted:
      "你仍然可以试听曲目；可以重试，或确认备份损坏文件后重置练习记录。"
    }
  }
}

private struct LibraryPracticeInvitationView: View {
  private static let benefits = [
    LibraryPracticeBenefit(
      title: "记录真实练习时长与练习次数",
      systemImage: "clock"
    ),
    LibraryPracticeBenefit(
      title: "追踪稳定、学习中与未练习小节",
      systemImage: "chart.bar.fill"
    ),
    LibraryPracticeBenefit(
      title: "自动发现值得继续关注的重点小节",
      systemImage: "sparkles"
    ),
  ]

  var body: some View {
    VStack(spacing: 20) {
      Spacer(minLength: 8)

      LibraryPracticeEmptyAnimationView()
        .frame(maxWidth: .infinity)

      VStack(spacing: 10) {
        Text("这首曲子还没有练习记录")
          .font(.title2)
          .bold()
          .multilineTextAlignment(.center)
          .foregroundStyle(.primary)

        Text("第一次弹下琴键，就是这首曲子的开始。完成一次真实练习后，这里会逐步记录你的进展。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 330)
      }
      .accessibilityElement(children: .combine)

      VStack(spacing: 9) {
        ForEach(Self.benefits) { benefit in
          LibraryPracticeBenefitRow(benefit: benefit)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("练习后可查看的信息")

      Label(
        "准备好后，从主窗口右下角开始练习",
        systemImage: "arrow.down.right"
      )
      .font(.subheadline)
      .bold()
      .foregroundStyle(.primary)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity)
      .background(.thinMaterial, in: .rect(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
      }
      .accessibilityElement(children: .combine)

      Spacer(minLength: 8)
    }
    .frame(maxWidth: .infinity)
    .containerRelativeFrame(.vertical, alignment: .center)
  }
}

private struct LibraryPracticeBenefit: Identifiable {
  var id: String { title }
  let title: String
  let systemImage: String
}

private struct LibraryPracticeBenefitRow: View {
  let benefit: LibraryPracticeBenefit

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: benefit.systemImage)
        .font(.body)
        .foregroundStyle(.tint)
        .frame(width: 32, height: 32)
        .background(.thinMaterial, in: .rect(cornerRadius: 10))
        .accessibilityHidden(true)

      Text(benefit.title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 12)
    .libraryPracticeCardSurface(cornerRadius: 15)
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryPracticeOverviewView: View {
  let overview: SongPracticeLibraryOverview

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LibraryPracticeOverviewHeader(status: overview.status)
        .padding(.bottom, 4)
      LibraryPracticeSummaryView(summary: overview.sessionSummary)

      switch overview.measureProgress {
      case let .available(progress):
        LibraryPracticeProgressSection(progress: progress)
      case .metadataUnavailable:
        LibraryPracticeProgressMessageSection(
          message: "下次成功准备曲谱后建立当前版本进度。"
        )
      }

      if let resume = overview.resumeSourceMeasureID {
        LibraryPracticeResumeSection(resume: resume)
      }

      if overview.focusMeasures.isEmpty == false {
        LibraryPracticeFocusSection(items: overview.focusMeasures)
      }

      if let streak = overview.sessionSummary.streak {
        LibraryPracticeEncouragementSection(
          streak: streak,
          stableMeasureCount: overview.measureProgress.stableMeasureCount
        )
      }
    }
  }
}

private struct LibraryPracticeOverviewHeader: View {
  let status: SongPracticeLibraryOverviewStatus

  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 5) {
        Text("CURRENT SONG")
          .font(.caption2)
          .bold()
          .tracking(1.1)
          .foregroundStyle(.secondary)

        Text("练习概览")
          .font(.title2)
          .bold()
          .foregroundStyle(.primary)
      }

      Spacer(minLength: 8)

      HStack(spacing: 7) {
        Image(systemName: status.systemImage)
          .accessibilityHidden(true)

        Text(status.title)
          .font(.caption)
          .bold()
      }
      .foregroundStyle(status.tint)
      .padding(.horizontal, 11)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: .capsule)
      .overlay {
        if differentiateWithoutColor || colorSchemeContrast == .increased {
          Capsule()
            .strokeBorder(Color.primary.opacity(0.32), lineWidth: 1)
        }
      }
      .accessibilityElement(children: .combine)
    }
  }

}

private struct LibraryPracticeSummaryView: View {
  let summary: SongPracticeSessionSummary

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 10) {
        LibraryPracticeSummaryCards(summary: summary)
      }
      VStack(spacing: 10) {
        LibraryPracticeSummaryCards(summary: summary)
      }
    }
  }
}

private struct LibraryPracticeSummaryCards: View {
  let summary: SongPracticeSessionSummary

  var body: some View {
    Group {
      LibraryPracticeMetricCard(
        title: "最近练习",
        value: summary.latestPracticeEndedAt?.formatted(
          date: .abbreviated,
          time: .omitted
        ) ?? "暂无"
      )
      LibraryPracticeMetricCard(
        title: "累计练习",
        value: summary.formattedActiveDuration
      )
      LibraryPracticeMetricCard(
        title: "练习次数",
        value: summary.sessionCount.formatted()
      )
    }
  }
}

private struct LibraryPracticeMetricCard: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Text(value)
        .font(.title3)
        .bold()
        .foregroundStyle(.primary)
        .minimumScaleFactor(0.76)
        .lineLimit(1)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
    .libraryPracticeCardSurface(cornerRadius: 16)
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryPracticeProgressSection: View {
  let progress: SongPracticeMeasureProgress

  var body: some View {
    LibraryPracticeSectionCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          Text("全曲进度")
            .font(.headline)
            .bold()

          Spacer()

          Text("\(progress.totalSourceMeasureCount.formatted()) 个小节 · 当前版本")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }

        LibraryPracticeSegmentedProgressBar(progress: progress)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("全曲进度")
          .accessibilityValue(progress.accessibilityValue)

        LibraryPracticeProgressLegend(progress: progress)
      }
    }
  }
}

private struct LibraryPracticeProgressLegend: View {
  let progress: SongPracticeMeasureProgress

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        LibraryPracticeLegendItems(progress: progress)
      }
      VStack(alignment: .leading, spacing: 10) {
        LibraryPracticeLegendItems(progress: progress)
      }
    }
  }
}

private struct LibraryPracticeLegendItems: View {
  let progress: SongPracticeMeasureProgress

  var body: some View {
    Group {
      LibraryPracticeLegendItem(
        title: "稳定",
        count: progress.stableSourceMeasureCount,
        systemImage: "checkmark.circle.fill",
        tint: .green
      )
      LibraryPracticeLegendItem(
        title: "学习中",
        count: progress.learningSourceMeasureCount,
        systemImage: "clock.fill",
        tint: .orange
      )
      LibraryPracticeLegendItem(
        title: "未练习",
        count: progress.unpracticedSourceMeasureCount,
        systemImage: "circle.dotted",
        tint: .secondary
      )
    }
  }
}

private struct LibraryPracticeSegmentedProgressBar: View {
  let progress: SongPracticeMeasureProgress

  var body: some View {
    Canvas { context, size in
      let bounds = CGRect(origin: .zero, size: size)
      context.fill(
        roundedPath(in: bounds, radius: size.height / 2),
        with: .color(Color.primary.opacity(0.14))
      )

      let segments = [
        LibraryPracticeProgressSegment(
          count: progress.stableSourceMeasureCount,
          tint: .green
        ),
        LibraryPracticeProgressSegment(
          count: progress.learningSourceMeasureCount,
          tint: .orange
        ),
        LibraryPracticeProgressSegment(
          count: progress.unpracticedSourceMeasureCount,
          tint: Color.primary.opacity(0.18)
        ),
      ].filter { $0.count > 0 }

      guard progress.totalSourceMeasureCount > 0, segments.isEmpty == false else { return }

      let spacing: CGFloat = 4
      let totalSpacing = spacing * CGFloat(max(segments.count - 1, 0))
      let availableWidth = max(size.width - totalSpacing, 0)
      var x: CGFloat = 0

      for segment in segments {
        let fraction = CGFloat(segment.count) / CGFloat(progress.totalSourceMeasureCount)
        let width = availableWidth * fraction
        let segmentRect = CGRect(x: x, y: 0, width: width, height: size.height)
        context.fill(
          roundedPath(in: segmentRect, radius: size.height / 2),
          with: .color(segment.tint)
        )
        x += width + spacing
      }
    }
    .frame(height: 11)
  }

  private func roundedPath(in rect: CGRect, radius: CGFloat) -> Path {
    var path = Path()
    path.addRoundedRect(
      in: rect,
      cornerSize: CGSize(width: radius, height: radius)
    )
    return path
  }
}

private struct LibraryPracticeProgressSegment {
  let count: Int
  let tint: Color
}

private struct LibraryPracticeLegendItem: View {
  let title: String
  let count: Int
  let systemImage: String
  let tint: Color

  var body: some View {
    Label {
      Text("\(title) · \(count.formatted())")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } icon: {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(count.formatted())
  }
}

private struct LibraryPracticeProgressMessageSection: View {
  let message: String

  var body: some View {
    LibraryPracticeSectionCard {
      Label {
        VStack(alignment: .leading, spacing: 5) {
          Text("当前版本进度待建立")
            .font(.headline)
            .bold()
          Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
    }
  }
}

private struct LibraryPracticeResumeSection: View {
  let resume: PracticeSourceMeasureID

  var body: some View {
    LibraryPracticeSectionCard {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text("上次练习位置")
            .font(.headline)
            .bold()
          Text("第 \(resume.libraryMeasureText) 小节")
            .font(.title2)
            .bold()
          Text("上次在这里结束，可以继续衔接。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        Image(systemName: "arrow.up.forward")
          .font(.title3)
          .foregroundStyle(.primary)
          .frame(width: 46, height: 46)
          .background(.thinMaterial, in: .rect(cornerRadius: 15))
          .accessibilityHidden(true)
      }
      .accessibilityElement(children: .combine)
    }
  }
}

private struct LibraryPracticeFocusSection: View {
  let items: [SongPracticeFocusMeasure]

  var body: some View {
    LibraryPracticeSectionCard {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("重点小节")
            .font(.headline)
            .bold()
          Spacer()
          Text("自动分析")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        VStack(spacing: 9) {
          ForEach(items.enumerated(), id: \.offset) { index, item in
            LibraryPracticeFocusRow(rank: index + 1, item: item)
          }
        }
      }
    }
  }
}

private struct LibraryPracticeFocusRow: View {
  let rank: Int
  let item: SongPracticeFocusMeasure

  var body: some View {
    HStack(spacing: 11) {
      Text(rank.formatted())
        .font(.caption)
        .bold()
        .foregroundStyle(.primary)
        .frame(width: 28, height: 28)
        .background(.thinMaterial, in: .rect(cornerRadius: 9))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("第 \(item.sourceMeasureID.libraryMeasureText) 小节")
          .font(.subheadline)
          .bold()
        Text(item.reason.libraryDisplayName)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .libraryPracticeCardSurface(cornerRadius: 14)
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryPracticeEncouragementSection: View {
  let streak: SongPracticeStreak
  let stableMeasureCount: Int

  var body: some View {
    LibraryPracticeSectionCard {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "sparkles")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 7) {
          Text(
            streak.recency == .current
              ? "已连续练习 \(streak.dayCount.formatted()) 天"
              : "最近连续练习 \(streak.dayCount.formatted()) 天"
          )
            .font(.headline)
            .bold()
            .frame(maxWidth: 280, alignment: .leading)
          Text(
            stableMeasureCount > 0
              ? "已经稳定掌握 \(stableMeasureCount.formatted()) 个小节。"
              : "每一次练习都在积累。"
          )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 300, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .combine)
    }
  }
}

private struct LibraryPracticeSectionCard<Content: View>: View {
  let cornerRadius: CGFloat
  let content: Content

  init(
    cornerRadius: CGFloat = LibraryPracticeOrnamentLayout.cardCornerRadius,
    @ViewBuilder content: () -> Content
  ) {
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .libraryPracticeCardSurface(cornerRadius: cornerRadius)
  }
}

private struct LibraryPracticeCardSurfaceModifier: ViewModifier {
  let cornerRadius: CGFloat

  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    content
      .background(.thinMaterial, in: .rect(cornerRadius: cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            Color.primary.opacity(0.14),
            lineWidth: differentiateWithoutColor || colorSchemeContrast == .increased ? 1.5 : 1
          )
      }
  }
}

extension View {
  fileprivate func libraryPracticeCardSurface(cornerRadius: CGFloat) -> some View {
    modifier(LibraryPracticeCardSurfaceModifier(cornerRadius: cornerRadius))
  }
}

extension SongPracticeLibraryOverviewStatus {
  fileprivate var title: String {
    switch self {
    case .learning: "正在学习"
    case .stable: "进展稳定"
    case .pending: "待建立进度"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .learning: "clock.fill"
    case .stable: "checkmark.circle.fill"
    case .pending: "sparkles"
    }
  }

  fileprivate var tint: Color {
    switch self {
    case .learning: .orange
    case .stable: .green
    case .pending: .secondary
    }
  }
}

extension SongPracticeSessionSummary {
  fileprivate var formattedActiveDuration: String {
    let duration = Duration.milliseconds(totalActiveDurationMilliseconds)
    if totalActiveDurationMilliseconds < 60_000 {
      return duration.formatted(.units(allowed: [.seconds], width: .abbreviated))
    }
    return duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }
}

extension SongPracticeMeasureProgressState {
  fileprivate var stableMeasureCount: Int {
    switch self {
    case let .available(progress): progress.stableSourceMeasureCount
    case .metadataUnavailable: 0
    }
  }
}

extension SongPracticeMeasureProgress {
  fileprivate var accessibilityValue: String {
    "稳定 \(stableSourceMeasureCount.formatted()) 个小节，学习中 \(learningSourceMeasureCount.formatted()) 个小节，未练习 \(unpracticedSourceMeasureCount.formatted()) 个小节，共 \(totalSourceMeasureCount.formatted()) 个小节"
  }
}

extension PracticeSourceMeasureID {
  fileprivate var libraryMeasureText: String {
    sourceNumberToken ?? (sourceMeasureIndex + 1).formatted()
  }
}

extension PracticeIssueKind {
  fileprivate var libraryDisplayName: String {
    switch self {
    case .wrongNote: "错音"
    case .missedNote: "漏音"
    case .incompleteChord: "和弦不完整"
    }
  }
}

extension SongPracticeFocusReason {
  fileprivate var libraryDisplayName: String {
    switch self {
    case let .recentIssue(issue): "近期\(issue.libraryDisplayName)"
    case let .failedAttempts(count): "失败 \(count.formatted()) 次"
    case .learning: "仍在学习"
    }
  }
}

#if DEBUG
  private struct LibraryPracticePreviewOrnament<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
      self.content = content()
    }

    var body: some View {
      ScrollView {
        content
          .padding(LibraryPracticeOrnamentLayout.contentPadding)
      }
      .scrollIndicators(.hidden)
      .frame(
        minWidth: LibraryPracticeOrnamentLayout.minimumWidth,
        idealWidth: LibraryPracticeOrnamentLayout.idealWidth,
        maxWidth: LibraryPracticeOrnamentLayout.maximumWidth,
        minHeight: 720,
        idealHeight: 720,
        maxHeight: 720
      )
      .glassBackgroundEffect()
    }
  }

  #Preview("练习概览") {
    LibraryPracticePreviewOrnament {
      LibraryPracticeOrnamentContentView(state: .overview(SongPracticeLibraryOverview(
        identity: SongPracticeLibrarySelectionIdentity(
          songID: UUID(),
          scoreFileVersionID: UUID()
        ),
        status: .learning,
        sessionSummary: SongPracticeSessionSummary(
          latestPracticeEndedAt: .now.addingTimeInterval(-86_400),
          totalActiveDurationMilliseconds: 2_520_000,
          sessionCount: 8,
          streak: SongPracticeStreak(dayCount: 3, recency: .current)
        ),
        measureProgress: .available(SongPracticeMeasureProgress(
          stableSourceMeasureCount: 10,
          learningSourceMeasureCount: 6,
          unpracticedSourceMeasureCount: 8
        )),
        resumeSourceMeasureID: PracticeSourceMeasureID(
          partID: "P1",
          sourceMeasureIndex: 17,
          sourceNumberToken: "18"
        ),
        focusMeasures: [
          SongPracticeFocusMeasure(
            sourceMeasureID: PracticeSourceMeasureID(
              partID: "P1",
              sourceMeasureIndex: 13,
              sourceNumberToken: "14"
            ),
            reason: .recentIssue(.wrongNote)
          ),
          SongPracticeFocusMeasure(
            sourceMeasureID: PracticeSourceMeasureID(
              partID: "P1",
              sourceMeasureIndex: 17,
              sourceNumberToken: "18"
            ),
            reason: .learning
          ),
        ]
      )), onRetry: {}, onConfirmedReset: {})
    }
  }

  #Preview("首次练习邀请") {
    LibraryPracticePreviewOrnament {
      LibraryPracticeOrnamentContentView(
        state: .invitation(SongPracticeLibrarySelectionIdentity(
          songID: UUID(),
          scoreFileVersionID: UUID()
        )),
        onRetry: {},
        onConfirmedReset: {}
      )
    }
  }
#endif
