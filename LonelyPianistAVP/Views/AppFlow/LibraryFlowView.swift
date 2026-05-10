import SwiftUI
import UniformTypeIdentifiers

struct LibraryFlowView: View {
    @Environment(AppRouter.self) private var router
    @Bindable var songLibraryViewModel: SongLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    router.exitToTypePicker(reason: "user tapped back from library")
                } label: {
                    HStack(spacing: 4) {
                        Text("重新选择钢琴类型")
                        if let kind = router.flowState.pianoKind {
                            Text("｜\(kind == .real ? "真实钢琴" : "虚拟钢琴")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            SongLibraryView(
                viewModel: songLibraryViewModel,
                onStartPractice: {
                    router.goToPractice()
                }
            )
        }
        .frame(minWidth: 560, idealWidth: 700)
        .fileImporter(
            isPresented: $songLibraryViewModel.isMusicXMLImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                songLibraryViewModel.importMusicXML(from: urls)
            } catch {
                songLibraryViewModel.errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}
