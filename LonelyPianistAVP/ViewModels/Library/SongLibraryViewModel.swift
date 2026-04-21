import Foundation
import Observation

@MainActor
@Observable
final class SongLibraryViewModel {
    private let appModel: AppModel
    private let indexStore: SongLibraryIndexStoreProtocol

    var index: SongLibraryIndex = .empty
    var errorMessage: String?

    init(
        appModel: AppModel,
        indexStore: SongLibraryIndexStoreProtocol? = nil
    ) {
        self.appModel = appModel
        self.indexStore = indexStore ?? SongLibraryIndexStore()
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
        errorMessage = "导入功能将在下一步接入。"
    }

    func didTapStartPractice(entryID: UUID) {
        guard index.entries.contains(where: { $0.id == entryID }) else { return }
        errorMessage = "开始练习流程将在下一步接入。"
    }
}
