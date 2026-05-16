import SwiftUI
import UniformTypeIdentifiers

struct LibraryFlowView: View {
    @Bindable var songLibraryViewModel: SongLibraryViewModel
    let selectedPianoModeTitle: String?
    let onBackToPreparation: @MainActor () -> Void
    let onStartPractice: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBackToPreparation()
                } label: {
                    HStack(spacing: 4) {
                        Text("重新选择钢琴类型")
                        if let selectedPianoModeTitle {
                            Text("｜\(selectedPianoModeTitle)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("导入 MusicXML") {
                    songLibraryViewModel.didTapImportMusicXML()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            SongLibraryView(
                viewModel: songLibraryViewModel,
                onStartPractice: {
                    onStartPractice()
                }
            )
        }
        .frame(minWidth: 700, idealWidth: 900, minHeight: 520, idealHeight: 700)
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
