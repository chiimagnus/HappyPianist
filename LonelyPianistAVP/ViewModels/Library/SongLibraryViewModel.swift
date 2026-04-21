import Foundation
import Observation

@MainActor
@Observable
final class SongLibraryViewModel {
    private let appModel: AppModel
    private let indexStore: SongLibraryIndexStoreProtocol
    private let fileStore: SongFileStoreProtocol
    private let paths: SongLibraryPaths
    private let parser: MusicXMLParserProtocol
    private let stepBuilder: PracticeStepBuilderProtocol

    var index: SongLibraryIndex = .empty
    var errorMessage: String?

    init(
        appModel: AppModel,
        indexStore: SongLibraryIndexStoreProtocol? = nil,
        fileStore: SongFileStoreProtocol? = nil,
        paths: SongLibraryPaths? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil
    ) {
        self.appModel = appModel
        self.indexStore = indexStore ?? SongLibraryIndexStore()
        self.fileStore = fileStore ?? SongFileStore()
        self.paths = paths ?? SongLibraryPaths()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        reload()
    }

    var entries: [SongLibraryEntry] {
        index.entries
    }

    func reload() {
        do {
            index = try indexStore.load()
        } catch {
            errorMessage = "加载乐曲库失败：\(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func didTapImportMusicXML() {
        // 由 View 层触发 fileImporter
    }

    func importMusicXML(from selectedURLs: [URL]) {
        guard selectedURLs.isEmpty == false else { return }

        do {
            var updatedIndex = try indexStore.load()

            for url in selectedURLs {
                let imported = try fileStore.importMusicXML(from: url)
                let entry = SongLibraryEntry(
                    id: UUID(),
                    displayName: URL(fileURLWithPath: imported.sourceFileName)
                        .deletingPathExtension()
                        .lastPathComponent,
                    musicXMLFileName: imported.storedFileName,
                    importedAt: imported.importedAt,
                    audioFileName: nil
                )
                updatedIndex.entries.append(entry)
            }

            try indexStore.save(updatedIndex)
            index = updatedIndex
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func preparePractice(entryID: UUID) -> Bool {
        guard let entry = index.entries.first(where: { $0.id == entryID }) else {
            return false
        }

        do {
            let scoreURL = try paths.scoresDirectoryURL().appendingPathComponent(entry.musicXMLFileName)
            let score = try parser.parse(fileURL: scoreURL)
            let buildResult = stepBuilder.buildSteps(from: score)

            guard buildResult.steps.isEmpty == false else {
                errorMessage = "该曲目未生成可练习步骤。"
                return false
            }

            appModel.setImportedSteps(
                buildResult.steps,
                file: ImportedMusicXMLFile(
                    fileName: entry.displayName,
                    storedURL: scoreURL,
                    importedAt: entry.importedAt
                )
            )

            var updatedIndex = index
            updatedIndex.lastSelectedEntryID = entry.id
            try? indexStore.save(updatedIndex)
            index = updatedIndex

            return true
        } catch {
            errorMessage = "加载曲目失败：\(error.localizedDescription)"
            return false
        }
    }
}
