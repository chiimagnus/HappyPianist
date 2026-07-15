import SwiftUI

struct LibraryPracticeProgressOrnamentView: View {
  static let minimumWidth: CGFloat = 360
  static let idealWidth: CGFloat = 420
  static let maximumWidth: CGFloat = 440

  let state: SongPracticeLibraryPresentationState

  var body: some View {
    ScrollView {
      LibraryPracticeOrnamentContentView(state: state)
        .padding(LibraryPracticeOrnamentLayout.contentPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .scrollIndicators(.hidden)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("当前曲目练习概览")
  }
}

private enum LibraryPracticeOrnamentLayout {
  static let contentPadding: CGFloat = 24
  static let cardCornerRadius: CGFloat = 22
}

private struct LibraryPracticeOrnamentContentView: View {
  let state: SongPracticeLibraryPresentationState

  var body: some View {
    switch state {
    case .loading:
      LibraryPracticeLoadingView()
    case .invitation:
      LibraryPracticeInvitationView()
    case .overview(let overview):
      LibraryPracticeOverviewView(
        presentation: LibraryPracticeOverviewPresentation(overview: overview)
      )
    case .unavailable:
      LibraryPracticeUnavailableView()
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
  var body: some View {
    ContentUnavailableView {
      Label("暂时无法读取练习记录", systemImage: "exclamationmark.triangle")
    } description: {
      Text("你仍然可以试听曲目或从主窗口开始练习；这里不会修改已有数据。")
    }
    .foregroundStyle(.primary)
    .frame(maxWidth: .infinity, minHeight: 420)
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
  let presentation: LibraryPracticeOverviewPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LibraryPracticeOverviewHeader(presentation: presentation)
        .padding(.bottom, 4)
      LibraryPracticeSummaryView(items: presentation.summaryItems)

      if let progress = presentation.progress {
        LibraryPracticeProgressSection(progress: progress)
      } else if let progressMessage = presentation.progressMessage {
        LibraryPracticeProgressMessageSection(message: progressMessage)
      }

      if let resume = presentation.resume {
        LibraryPracticeResumeSection(resume: resume)
      }

      if presentation.focusItems.isEmpty == false {
        LibraryPracticeFocusSection(items: presentation.focusItems)
      }

      if let encouragement = presentation.encouragement {
        LibraryPracticeEncouragementSection(encouragement: encouragement)
      }
    }
  }
}

private struct LibraryPracticeOverviewHeader: View {
  let presentation: LibraryPracticeOverviewPresentation

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
        Image(systemName: presentation.status.systemImage)
          .accessibilityHidden(true)

        Text(presentation.status.title)
          .font(.caption)
          .bold()
      }
      .foregroundStyle(presentation.status.tint)
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
  let items: [LibraryPracticeSummaryItem]

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 10))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 10))

    layout {
      ForEach(items) { item in
        LibraryPracticeMetricCard(item: item)
      }
    }
  }
}

private struct LibraryPracticeMetricCard: View {
  let item: LibraryPracticeSummaryItem

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(item.title)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Text(item.value)
        .font(.title3)
        .bold()
        .foregroundStyle(.primary)
        .minimumScaleFactor(0.76)
        .lineLimit(1)

      if let note = item.note {
        Text(note)
          .font(.caption2)
          .foregroundStyle(.secondary.opacity(0.74))
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
    .libraryPracticeCardSurface(cornerRadius: 16)
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryPracticeProgressSection: View {
  let progress: LibraryPracticeMeasureProgress

  var body: some View {
    LibraryPracticeSectionCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          Text("全曲进度")
            .font(.headline)
            .bold()

          Spacer()

          Text("\(progress.total.formatted()) 个小节 · \(progress.handModeText)")
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
  let progress: LibraryPracticeMeasureProgress

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(spacing: 8))

    layout {
      LibraryPracticeLegendItem(
        title: "稳定",
        count: progress.stable,
        systemImage: "checkmark.circle.fill",
        tint: .green
      )
      LibraryPracticeLegendItem(
        title: "学习中",
        count: progress.learning,
        systemImage: "clock.fill",
        tint: .orange
      )
      LibraryPracticeLegendItem(
        title: "未练习",
        count: progress.unpracticed,
        systemImage: "circle.dotted",
        tint: .secondary
      )
    }
  }
}

private struct LibraryPracticeSegmentedProgressBar: View {
  let progress: LibraryPracticeMeasureProgress

  var body: some View {
    Canvas { context, size in
      let bounds = CGRect(origin: .zero, size: size)
      context.fill(
        roundedPath(in: bounds, radius: size.height / 2),
        with: .color(Color.primary.opacity(0.14))
      )

      let segments = [
        LibraryPracticeProgressSegment(
          count: progress.stable,
          tint: .green
        ),
        LibraryPracticeProgressSegment(
          count: progress.learning,
          tint: .orange
        ),
        LibraryPracticeProgressSegment(
          count: progress.unpracticed,
          tint: Color.primary.opacity(0.18)
        ),
      ].filter { $0.count > 0 }

      guard progress.total > 0, segments.isEmpty == false else { return }

      let spacing: CGFloat = 4
      let totalSpacing = spacing * CGFloat(max(segments.count - 1, 0))
      let availableWidth = max(size.width - totalSpacing, 0)
      var x: CGFloat = 0

      for segment in segments {
        let fraction = CGFloat(segment.count) / CGFloat(progress.total)
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
  let resume: LibraryPracticeResumePresentation

  var body: some View {
    LibraryPracticeSectionCard {
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text("上次练习位置")
            .font(.headline)
            .bold()
          Text(resume.measureText)
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
  let items: [LibraryPracticeFocusItem]

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
          ForEach(items) { item in
            LibraryPracticeFocusRow(item: item)
          }
        }
      }
    }
  }
}

private struct LibraryPracticeFocusRow: View {
  let item: LibraryPracticeFocusItem

  var body: some View {
    HStack(spacing: 11) {
      Text(item.rank.formatted())
        .font(.caption)
        .bold()
        .foregroundStyle(.primary)
        .frame(width: 28, height: 28)
        .background(.thinMaterial, in: .rect(cornerRadius: 9))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.subheadline)
          .bold()
        Text(item.detail)
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
  let encouragement: LibraryPracticeEncouragementPresentation

  var body: some View {
    LibraryPracticeSectionCard {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "sparkles")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 7) {
          Text(encouragement.title)
            .font(.headline)
            .bold()
            .frame(maxWidth: 280, alignment: .leading)
          Text(encouragement.message)
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

private struct LibraryPracticeOverviewPresentation {
  enum Status {
    case learning
    case stable
    case pending

    var title: String {
      switch self {
      case .learning: "正在学习"
      case .stable: "进展稳定"
      case .pending: "待建立进度"
      }
    }

    var systemImage: String {
      switch self {
      case .learning: "clock.fill"
      case .stable: "checkmark.circle.fill"
      case .pending: "sparkles"
      }
    }

    var tint: Color {
      switch self {
      case .learning: .orange
      case .stable: .green
      case .pending: .secondary
      }
    }
  }

  let status: Status
  let summaryItems: [LibraryPracticeSummaryItem]
  let progress: LibraryPracticeMeasureProgress?
  let progressMessage: String?
  let resume: LibraryPracticeResumePresentation?
  let focusItems: [LibraryPracticeFocusItem]
  let encouragement: LibraryPracticeEncouragementPresentation?

  init(overview: SongPracticeLibraryOverview) {
    let availableProgress = switch overview.measureProgress {
    case let .available(progress): progress
    case .metadataUnavailable: nil
    }
    let stableCount = availableProgress?.stableSourceMeasureCount ?? 0
    let learningCount = availableProgress?.learningSourceMeasureCount ?? 0
    let totalCount = availableProgress?.totalSourceMeasureCount ?? 0
    let latestPracticeText =
      overview.sessionSummary.latestPracticeEndedAt.map {
        $0.formatted(date: .abbreviated, time: .omitted)
      } ?? "暂无"

    status = Self.status(
      stableCount: stableCount,
      learningCount: learningCount,
      totalCount: totalCount,
      hasCurrentFacts: availableProgress != nil
    )

    summaryItems = [
      LibraryPracticeSummaryItem(
        id: "latest",
        title: "最近练习",
        value: latestPracticeText,
        note: nil
      ),
      LibraryPracticeSummaryItem(
        id: "duration",
        title: "累计练习",
        value: Self.durationText(overview.sessionSummary.totalActiveDurationMilliseconds),
        note: nil
      ),
      LibraryPracticeSummaryItem(
        id: "sessions",
        title: "练习次数",
        value: overview.sessionSummary.sessionCount.formatted(),
        note: nil
      ),
    ]

    if totalCount > 0 {
      progress = LibraryPracticeMeasureProgress(
        total: totalCount,
        stable: stableCount,
        learning: learningCount,
        handModeText: "当前版本"
      )
      progressMessage = nil
    } else {
      progress = nil
      progressMessage = switch overview.measureProgress {
      case .metadataUnavailable: "下次成功准备曲谱后建立当前版本进度。"
      case .available: "当前曲谱尚无可统计的小节。"
      }
    }

    resume = overview.resumeSourceMeasureID.map {
      LibraryPracticeResumePresentation(
        measureText: "第 \($0.libraryMeasureText) 小节"
      )
    }

    focusItems =
      overview.focusMeasures.enumerated().map { index, focus in
        LibraryPracticeFocusItem(
          rank: index + 1,
          title: "第 \(focus.sourceMeasureID.libraryMeasureText) 小节",
          detail: switch focus.reason {
          case let .recentIssue(issue): "近期\(issue.libraryDisplayName)"
          case let .failedAttempts(count): "失败 \(count.formatted()) 次"
          case .learning: "仍在学习"
          }
        )
      }

    if let streak = overview.sessionSummary.streak {
      encouragement = LibraryPracticeEncouragementPresentation(
        title: streak.recency == .current
          ? "已连续练习 \(streak.dayCount.formatted()) 天"
          : "最近连续练习 \(streak.dayCount.formatted()) 天",
        message: stableCount > 0
          ? "已经稳定掌握 \(stableCount.formatted()) 个小节。"
          : "每一次练习都在积累。"
      )
    } else {
      encouragement = nil
    }
  }

  private static func durationText(_ milliseconds: Int64) -> String {
    let duration = Duration.milliseconds(milliseconds)
    if milliseconds < 60_000 {
      return duration.formatted(.units(allowed: [.seconds], width: .abbreviated))
    }
    return duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }

  private init(
    status: Status,
    summaryItems: [LibraryPracticeSummaryItem],
    progress: LibraryPracticeMeasureProgress?,
    progressMessage: String?,
    resume: LibraryPracticeResumePresentation?,
    focusItems: [LibraryPracticeFocusItem],
    encouragement: LibraryPracticeEncouragementPresentation?
  ) {
    self.status = status
    self.summaryItems = summaryItems
    self.progress = progress
    self.progressMessage = progressMessage
    self.resume = resume
    self.focusItems = focusItems
    self.encouragement = encouragement
  }

  private static func status(
    stableCount: Int,
    learningCount: Int,
    totalCount: Int,
    hasCurrentFacts: Bool
  ) -> Status {
    guard hasCurrentFacts else { return .pending }
    if totalCount > 0, stableCount == totalCount, learningCount == 0 {
      return .stable
    }
    return .learning
  }
}

private struct LibraryPracticeSummaryItem: Identifiable {
  let id: String
  let title: String
  let value: String
  let note: String?
}

private struct LibraryPracticeMeasureProgress {
  let total: Int
  let stable: Int
  let learning: Int
  let handModeText: String

  init(total: Int, stable: Int, learning: Int, handModeText: String) {
    let safeTotal = max(total, 0)
    let safeStable = min(max(stable, 0), safeTotal)
    let safeLearning = min(max(learning, 0), safeTotal - safeStable)

    self.total = safeTotal
    self.stable = safeStable
    self.learning = safeLearning
    self.handModeText = handModeText
  }

  var unpracticed: Int {
    total - stable - learning
  }

  var accessibilityValue: String {
    "稳定 \(stable.formatted()) 个小节，学习中 \(learning.formatted()) 个小节，未练习 \(unpracticed.formatted()) 个小节，共 \(total.formatted()) 个小节"
  }
}

private struct LibraryPracticeResumePresentation {
  let measureText: String
}

private struct LibraryPracticeFocusItem: Identifiable {
  var id: Int { rank }
  let rank: Int
  let title: String
  let detail: String
}

private struct LibraryPracticeEncouragementPresentation {
  let title: String
  let message: String
}

extension PracticeHandMode {
  fileprivate var libraryDisplayName: String {
    switch self {
    case .both: "双手"
    case .right: "右手"
    case .left: "左手"
    }
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

#if DEBUG
  extension LibraryPracticeOverviewPresentation {
    fileprivate static let preview = LibraryPracticeOverviewPresentation(
      status: .learning,
      summaryItems: [
        LibraryPracticeSummaryItem(
          id: "latest",
          title: "最近练习",
          value: "昨天",
          note: nil
        ),
        LibraryPracticeSummaryItem(
          id: "duration",
          title: "累计练习",
          value: "42 分钟",
          note: nil
        ),
        LibraryPracticeSummaryItem(
          id: "sessions",
          title: "练习次数",
          value: "8 次",
          note: nil
        ),
      ],
      progress: LibraryPracticeMeasureProgress(
        total: 24,
        stable: 10,
        learning: 6,
        handModeText: "双手"
      ),
      progressMessage: nil,
      resume: LibraryPracticeResumePresentation(measureText: "第 18 小节"),
      focusItems: [
        LibraryPracticeFocusItem(
          rank: 1,
          title: "第 14 小节",
          detail: "近期错误较多 · 右手节奏"
        ),
        LibraryPracticeFocusItem(
          rank: 2,
          title: "第 18 小节",
          detail: "仍在学习 · 双手配合"
        ),
        LibraryPracticeFocusItem(
          rank: 3,
          title: "第 21 小节",
          detail: "最近练习 · 稳定度不足"
        ),
      ],
      encouragement: LibraryPracticeEncouragementPresentation(
        title: "已经连续练习 3 天",
        message: "保持这个节奏。你正在把困难的小节变成身体记忆。"
      )
    )
  }

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
        minWidth: LibraryPracticeProgressOrnamentView.minimumWidth,
        idealWidth: LibraryPracticeProgressOrnamentView.idealWidth,
        maxWidth: LibraryPracticeProgressOrnamentView.maximumWidth,
        minHeight: 720,
        idealHeight: 720,
        maxHeight: 720
      )
      .glassBackgroundEffect()
    }
  }

  #Preview("练习概览") {
    LibraryPracticePreviewOrnament {
      LibraryPracticeOverviewView(presentation: .preview)
    }
  }

  #Preview("首次练习邀请") {
    LibraryPracticePreviewOrnament {
      LibraryPracticeInvitationView()
    }
  }
#endif
