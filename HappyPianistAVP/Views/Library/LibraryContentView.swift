import SwiftUI
import UniformTypeIdentifiers

struct LibraryContentView: View {
    @Bindable var songLibraryViewModel: SongLibraryViewModel
    let onBackToPreparation: @MainActor () -> Void
    let onStartPractice: @MainActor () -> Void

    var body: some View {
        SongLibraryView(
            viewModel: songLibraryViewModel,
            onBackToPreparation: onBackToPreparation,
            onStartPractice: onStartPractice
        )
        .fileImporter(
            isPresented: $songLibraryViewModel.isMusicXMLImporterPresented,
            allowedContentTypes: [.xml, .musicXML, .compressedMusicXML],
            allowsMultipleSelection: true
        ) { result in
            do {
                songLibraryViewModel.importMusicXML(from: try result.get())
            } catch {
                songLibraryViewModel.errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}
