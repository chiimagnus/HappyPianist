import Foundation
import Observation

@MainActor
@Observable
final class TakeLibraryViewModel {
    private let store: RecordingTakeStoreProtocol

    var takes: [RecordingTake] = []
    var selectedTakeID: UUID?
    var errorMessage: String?

    init(store: RecordingTakeStoreProtocol? = nil) {
        self.store = store ?? RecordingTakeStore()
        reload()
    }

    func reload() {
        do {
            takes = try store.load()
        } catch {
            errorMessage = "加载录制库失败：\(error.localizedDescription)"
        }
    }

    func addTake(_ take: RecordingTake) {
        do {
            var updated = takes
            updated.insert(take, at: 0)
            try store.save(updated)
            takes = updated
        } catch {
            errorMessage = "保存录制失败：\(error.localizedDescription)"
        }
    }

    func rename(takeID: UUID, to newName: String) {
        guard let index = takes.firstIndex(where: { $0.id == takeID }) else { return }
        do {
            var updated = takes
            updated[index].name = newName
            try store.save(updated)
            takes = updated
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
        }
    }

    func delete(takeID: UUID) {
        guard let index = takes.firstIndex(where: { $0.id == takeID }) else { return }
        do {
            var updated = takes
            updated.remove(at: index)
            try store.save(updated)
            takes = updated
            if selectedTakeID == takeID {
                selectedTakeID = nil
            }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func clearAll() {
        do {
            try store.save([])
            takes = []
            selectedTakeID = nil
        } catch {
            errorMessage = "清空失败：\(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
