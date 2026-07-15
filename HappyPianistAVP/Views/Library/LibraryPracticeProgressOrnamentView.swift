import SwiftUI

struct LibraryPracticeProgressOrnamentView: View {
  let state: SongPracticeLibraryPresentationState

  var body: some View {
    ScrollView {
      LibraryPracticeOrnamentContentView(state: state)
        .padding(LibraryDesignTokens.practiceOrnamentContentPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .scrollIndicators(.hidden)
    .clipShape(.rect(cornerRadius: LibraryDesignTokens.practiceOrnamentCornerRadius))
    .containerShape(.rect(cornerRadius: LibraryDesignTokens.practiceOrnamentCornerRadius))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("当前曲目练习概览")
  }
}

private struct LibraryPracticeOrnamentContentView: View {
  let state: SongPracticeLibraryPresentationState

  var body: some View {
    switch state {
    case .loading:
      LibraryPracticeLoadingView()
    case .neverPracticed:
      LibraryPracticeInvitationView()
    case .current(let snapshot):
      LibraryPracticeOverviewView(
        presentation: LibraryPracticeOverviewPresentation(snapshot: snapshot)
      )
    case .needsRebuild(_, let historyDate):
      LibraryPracticeOverviewView(
        presentation: LibraryPracticeOverviewPresentation.needsRebuild(
          historyDate: historyDate
        )
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
          .tint(LibraryDesignTokens.practiceAccent)

        VStack(alignment: .leading, spacing: 4) {
          Text("正在读取练习记录")
            .font(.headline)
            .bold()
          Text("正在准备当前曲目的练习概览。")
            .font(.subheadline)
            .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
        }
      }
      .accessibilityElement(children: .combine)

      LibraryPracticeLoadingPlaceholderView()
      LibraryPracticeLoadingPlaceholderView()
      LibraryPracticeLoadingPlaceholderView()
    }
    .padding(.top, 4)
  }
}

private struct LibraryPracticeLoadingPlaceholderView: View {
  var body: some View {
    RoundedRectangle(cornerRadius: LibraryDesignTokens.practiceCardCornerRadius)
      .fill(.thinMaterial)
      .frame(height: 92)
      .overlay(alignment: .leading) {
        VStack(alignment: .leading, spacing: 10) {
          Capsule()
            .fill(LibraryDesignTokens.practiceInk.opacity(0.16))
            .frame(width: 96, height: 10)
          Capsule()
            .fill(LibraryDesignTokens.practiceInk.opacity(0.09))
            .frame(maxWidth: .infinity)
            .frame(height: 9)
        }
        .padding(18)
      }
      .overlay {
        RoundedRectangle(cornerRadius: LibraryDesignTokens.practiceCardCornerRadius)
          .strokeBorder(LibraryDesignTokens.practiceLine, lineWidth: 1)
      }
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
    .foregroundStyle(LibraryDesignTokens.practiceInk)
    .frame(maxWidth: .infinity, minHeight: 420)
  }
}

private struct LibraryPracticeInvitationView: View {
  private let benefits = [
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
          .foregroundStyle(LibraryDesignTokens.practiceInk)

        Text("第一次弹下琴键，就是这首曲子的开始。完成一次真实练习后，这里会逐步记录你的进展。")
          .font(.subheadline)
          .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
          .multilineTextAlignment(.center)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 330)
      }
      .accessibilityElement(children: .combine)

      VStack(spacing: 9) {
        ForEach(benefits) { benefit in
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
      .foregroundStyle(LibraryDesignTokens.practiceAccentDeep)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity)
      .background {
        RoundedRectangle(cornerRadius: 16)
          .fill(.thinMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 16)
              .fill(LibraryDesignTokens.practiceAccent.opacity(0.12))
          }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(LibraryDesignTokens.practiceAccent.opacity(0.28), lineWidth: 1)
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
        .foregroundStyle(LibraryDesignTokens.practiceAccentDeep)
        .frame(width: 32, height: 32)
        .background(
          LibraryDesignTokens.practiceAccent.opacity(0.13),
          in: .rect(cornerRadius: 10)
        )
        .accessibilityHidden(true)

      Text(benefit.title)
        .font(.subheadline)
        .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 12)
    .background(.thinMaterial, in: .rect(cornerRadius: 15))
    .overlay {
      RoundedRectangle(cornerRadius: 15)
        .strokeBorder(LibraryDesignTokens.practiceLine, lineWidth: 1)
    }
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
          .foregroundStyle(LibraryDesignTokens.practiceAccent)

        Text("练习概览")
          .font(.title2)
          .bold()
          .foregroundStyle(LibraryDesignTokens.practiceInk)
      }

      Spacer(minLength: 8)

      HStack(spacing: 7) {
        Circle()
          .fill(presentation.status.tint)
          .frame(width: 8, height: 8)
          .overlay {
            Circle()
              .strokeBorder(presentation.status.tint.opacity(0.18), lineWidth: 5)
          }
          .accessibilityHidden(true)

        Text(presentation.status.title)
          .font(.caption)
          .bold()
      }
      .foregroundStyle(presentation.status.tint)
      .padding(.horizontal, 11)
      .padding(.vertical, 8)
      .background {
        Capsule()
          .fill(.thinMaterial)
          .overlay {
            Capsule()
              .fill(presentation.status.tint.opacity(0.10))
          }
      }
      .overlay {
        if differentiateWithoutColor || colorSchemeContrast == .increased {
          Capsule()
            .strokeBorder(presentation.status.tint.opacity(0.65), lineWidth: 1)
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
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: 10) {
        ForEach(items) { item in
          LibraryPracticeMetricCard(item: item)
        }
      }
    } else {
      HStack(alignment: .top, spacing: 10) {
        ForEach(items) { item in
          LibraryPracticeMetricCard(item: item)
        }
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
        .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
        .lineLimit(2)

      Text(item.value)
        .font(.title3)
        .bold()
        .foregroundStyle(LibraryDesignTokens.practiceInk)
        .minimumScaleFactor(0.76)
        .lineLimit(1)

      if let note = item.note {
        Text(note)
          .font(.caption2)
          .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk.opacity(0.74))
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
    .background(.thinMaterial, in: .rect(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(LibraryDesignTokens.practiceLine, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryPracticeProgressSection: View {
  let progress: LibraryPracticeMeasureProgress

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
            .multilineTextAlignment(.trailing)
        }

        LibraryPracticeSegmentedProgressBar(progress: progress)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("全曲进度")
          .accessibilityValue(progress.accessibilityValue)

        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 10) {
            legendItems
          }
        } else {
          HStack(spacing: 8) {
            legendItems
          }
        }
      }
    }
  }

  @ViewBuilder
  private var legendItems: some View {
    LibraryPracticeLegendItem(
      title: "稳定",
      count: progress.stable,
      systemImage: "checkmark.circle.fill",
      tint: LibraryDesignTokens.practiceStable
    )
    LibraryPracticeLegendItem(
      title: "学习中",
      count: progress.learning,
      systemImage: "clock.fill",
      tint: LibraryDesignTokens.practiceLearning
    )
    LibraryPracticeLegendItem(
      title: "未练习",
      count: progress.unpracticed,
      systemImage: "circle.dotted",
      tint: LibraryDesignTokens.practiceUnpracticedInk
    )
  }
}

private struct LibraryPracticeSegmentedProgressBar: View {
  let progress: LibraryPracticeMeasureProgress

  var body: some View {
    Canvas { context, size in
      let bounds = CGRect(origin: .zero, size: size)
      context.fill(
        roundedPath(in: bounds, radius: size.height / 2),
        with: .color(LibraryDesignTokens.practiceUnpracticed)
      )

      let segments = [
        LibraryPracticeProgressSegment(
          count: progress.stable,
          tint: LibraryDesignTokens.practiceStable
        ),
        LibraryPracticeProgressSegment(
          count: progress.learning,
          tint: LibraryDesignTokens.practiceLearning
        ),
        LibraryPracticeProgressSegment(
          count: progress.unpracticed,
          tint: LibraryDesignTokens.practiceUnpracticed
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
        .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
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
            .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
        }
      } icon: {
        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
          .foregroundStyle(LibraryDesignTokens.practiceAccent)
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
            .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
        }

        Spacer(minLength: 12)

        Image(systemName: "arrow.up.forward")
          .font(.title3)
          .foregroundStyle(LibraryDesignTokens.practiceAccentDeep)
          .frame(width: 46, height: 46)
          .background(
            LibraryDesignTokens.practiceAccent.opacity(0.13),
            in: .rect(cornerRadius: 15)
          )
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
            .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
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
        .foregroundStyle(LibraryDesignTokens.practiceAccentDeep)
        .frame(width: 28, height: 28)
        .background(
          LibraryDesignTokens.practiceAccent.opacity(0.14),
          in: .rect(cornerRadius: 9)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(item.title)
          .font(.subheadline)
          .bold()
        Text(item.detail)
          .font(.caption)
          .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .background(.thinMaterial, in: .rect(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(LibraryDesignTokens.practiceLine.opacity(0.72), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct LibraryPracticeEncouragementSection: View {
  let encouragement: LibraryPracticeEncouragementPresentation

  var body: some View {
    LibraryPracticeSectionCard(accented: true) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "sparkles")
          .font(.largeTitle)
          .foregroundStyle(LibraryDesignTokens.practiceAccent.opacity(0.42))
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 7) {
          Text(encouragement.title)
            .font(.headline)
            .bold()
            .frame(maxWidth: 280, alignment: .leading)
          Text(encouragement.message)
            .font(.subheadline)
            .foregroundStyle(LibraryDesignTokens.practiceSecondaryInk)
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
  let accented: Bool
  let content: Content

  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  init(
    cornerRadius: CGFloat = LibraryDesignTokens.practiceCardCornerRadius,
    accented: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.cornerRadius = cornerRadius
    self.accented = accented
    self.content = content()
  }

  var body: some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(.thinMaterial)
          .overlay {
            if accented {
              RoundedRectangle(cornerRadius: cornerRadius)
                .fill(LibraryDesignTokens.practiceAccent.opacity(0.10))
            }
          }
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            LibraryDesignTokens.practiceLine,
            lineWidth: differentiateWithoutColor || colorSchemeContrast == .increased ? 1.5 : 1
          )
      }
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
      case .learning: LibraryDesignTokens.accent
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

  init(snapshot: SongPracticeLibrarySnapshot) {
    let facts = snapshot.currentFacts
    let stableCount = facts?.stableSourceMeasureCount ?? 0
    let learningCount = facts?.learningSourceMeasureCount ?? 0
    let latestPracticeText =
      snapshot.latestPracticeDate.map {
        $0.formatted(date: .abbreviated, time: .omitted)
      } ?? "暂无"

    status = Self.status(
      stableCount: stableCount,
      learningCount: learningCount,
      totalCount: snapshot.totalSourceMeasureCount,
      hasCurrentFacts: facts != nil
    )

    summaryItems = [
      LibraryPracticeSummaryItem(
        id: "latest",
        title: "最近练习",
        value: latestPracticeText,
        note: nil
      ),
      LibraryPracticeSummaryItem(
        id: "stable",
        title: "稳定小节",
        value: stableCount.formatted(),
        note: "当前版本"
      ),
      LibraryPracticeSummaryItem(
        id: "learning",
        title: "练习中",
        value: learningCount.formatted(),
        note: facts?.handMode.libraryDisplayName
      ),
    ]

    if snapshot.totalSourceMeasureCount > 0 {
      progress = LibraryPracticeMeasureProgress(
        total: snapshot.totalSourceMeasureCount,
        stable: stableCount,
        learning: learningCount,
        handModeText: facts?.handMode.libraryDisplayName ?? "当前版本"
      )
      progressMessage = nil
    } else {
      progress = nil
      progressMessage = "开始一次练习后会建立当前曲谱结构。"
    }

    resume = facts?.resumeSourceMeasureID.map {
      LibraryPracticeResumePresentation(
        measureText: "第 \($0.libraryMeasureText) 小节"
      )
    }

    focusItems =
      facts?.recentIssues.prefix(3).enumerated().map { index, issue in
        LibraryPracticeFocusItem(
          rank: index + 1,
          title: "第 \(issue.sourceMeasureID.libraryMeasureText) 小节",
          detail:
            "近期\(issue.kind.libraryDisplayName) · \(issue.attemptedAt.formatted(date: .abbreviated, time: .omitted))"
        )
      } ?? []

    if stableCount > 0 {
      encouragement = LibraryPracticeEncouragementPresentation(
        title: "已经稳定掌握 \(stableCount.formatted()) 个小节",
        message: "保持这个节奏。你正在把困难的小节变成身体记忆。"
      )
    } else if facts != nil {
      encouragement = LibraryPracticeEncouragementPresentation(
        title: "每一次练习都在积累",
        message: "继续完成当前小节，稳定进度会逐步出现在这里。"
      )
    } else {
      encouragement = nil
    }
  }

  static func needsRebuild(historyDate: Date?) -> LibraryPracticeOverviewPresentation {
    let latestText =
      historyDate.map {
        $0.formatted(date: .abbreviated, time: .omitted)
      } ?? "已保留"

    return LibraryPracticeOverviewPresentation(
      status: .pending,
      summaryItems: [
        LibraryPracticeSummaryItem(
          id: "latest",
          title: "最近练习",
          value: latestText,
          note: nil
        ),
        LibraryPracticeSummaryItem(
          id: "progress",
          title: "当前进度",
          value: "待建立",
          note: nil
        ),
        LibraryPracticeSummaryItem(
          id: "history",
          title: "历史记录",
          value: "已保留",
          note: nil
        ),
      ],
      progress: nil,
      progressMessage: "历史练习事实已经保留。开始一次练习后，会按当前曲谱版本重新建立小节进度。",
      resume: nil,
      focusItems: [],
      encouragement: LibraryPracticeEncouragementPresentation(
        title: "可以从当前版本重新开始",
        message: "历史练习不会丢失，新的小节进度会在练习后逐步建立。"
      )
    )
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
          .padding(LibraryDesignTokens.practiceOrnamentContentPadding)
      }
      .scrollIndicators(.hidden)
      .clipShape(.rect(cornerRadius: LibraryDesignTokens.practiceOrnamentCornerRadius))
      .containerShape(.rect(cornerRadius: LibraryDesignTokens.practiceOrnamentCornerRadius))
      .frame(
        minWidth: LibraryDesignTokens.practiceOrnamentMinimumWidth,
        idealWidth: LibraryDesignTokens.practiceOrnamentIdealWidth,
        maxWidth: LibraryDesignTokens.practiceOrnamentMaximumWidth,
        minHeight: 720,
        idealHeight: 720,
        maxHeight: 720
      )
      .glassBackgroundEffect(
        in: .rect(cornerRadius: LibraryDesignTokens.practiceOrnamentCornerRadius)
      )
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
