import Notation
import SwiftUI

struct SpatialLibraryFolioAttachmentView: View {
    let presentation: SongLibraryTrackPresentation
    let isPlaying: Bool
    let onConfirm: @MainActor () -> Void

    var body: some View {
        Button(action: onConfirm) {
            LibraryScoreFolioView(
                presentation: presentation,
                isPlaying: isPlaying
            )
            .frame(width: 220, height: 308)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }
}

struct SpatialLibrarySpreadAttachmentView: View {
    @Bindable var library: SongLibraryViewModel

    private let renderHeight: CGFloat = 640

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch library.scorePreview.state {
                case .idle:
                    EmptyView()

                case .loading:
                    ProgressView("正在打开曲谱")

                case let .failure(failure):
                    ContentUnavailableView {
                        Label(
                            failure.title,
                            systemImage: "exclamationmark.triangle"
                        )
                    } description: {
                        Text(failure.explanation)
                    } actions: {
                        Button(
                            "重试",
                            systemImage: "arrow.clockwise",
                            action: library.openSelectedScore
                        )
                    }

                case .ready:
                    if let plan = library.scorePreview.pageOwner.plan,
                       let identity = library.scorePreview.identity
                    {
                        GrandStaffNotationSpreadView(
                            plan: plan,
                            targetIndex: library.scorePreview.targetSpreadIndex,
                            annotations: annotations(
                                plan: plan,
                                identity: identity
                            ),
                            onTurnBackward: library.scorePreview.canTurnBackward
                                ? { library.scorePreview.turn(forward: false) }
                                : nil,
                            onTurnForward: library.scorePreview.canTurnForward
                                ? { library.scorePreview.turn(forward: true) }
                                : nil
                        )
                    }
                }
            }
            .frame(
                width: renderHeight * spreadAspectRatio,
                height: renderHeight
            )

            Button("返回曲库", systemImage: "books.vertical") {
                library.scorePreview.close()
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .padding(18)
        }
    }

    private var spreadAspectRatio: CGFloat {
        CGFloat(
            GrandStaffNotationPageGeometry.canonical.spreadWidth
                / GrandStaffNotationPageGeometry.canonical.height
        )
    }

    private func annotations(
        plan: GrandStaffNotationPagePlan,
        identity: SongPracticeLibrarySelectionIdentity
    ) -> [GrandStaffNotationMeasureAnnotation] {
        guard case let .overview(overview) = library.practiceSnapshotState else {
            return []
        }
        return LibraryScorePreviewViewModel.annotations(
            overview: overview,
            plan: plan,
            selection: identity
        )
    }
}
