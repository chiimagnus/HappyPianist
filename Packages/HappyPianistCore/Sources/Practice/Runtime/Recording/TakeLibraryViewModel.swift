import Foundation
import Observation

@MainActor
@Observable
public final class TakeLibraryViewModel {
    private let store: any RecordingTakeStoreProtocol
    private let midiExportService: any RecordingMIDIExportServiceProtocol

    public var takes: [RecordingTake] = []
    public var selectedTakeID: UUID?
    public var errorMessage: String?

    public init(
        store: (any RecordingTakeStoreProtocol)? = nil,
        midiExportService: (any RecordingMIDIExportServiceProtocol)? = nil
    ) {
        self.store = store ?? RecordingTakeStore()
        self.midiExportService = midiExportService ?? RecordingMIDIExportService()
        reload()
    }

    public func reload() {
        do {
            takes = try store.load()
            errorMessage = nil
        } catch {
            errorMessage = "加载录制库失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    public func addTake(_ take: RecordingTake) -> Bool {
        do {
            var updated = takes
            updated.insert(take, at: 0)
            try store.save(updated)
            takes = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存录制失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    public func rename(takeID: UUID, to newName: String) -> Bool {
        guard let index = takes.firstIndex(where: { $0.id == takeID }) else { return false }
        do {
            var updated = takes
            updated[index].name = newName
            try store.save(updated)
            takes = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = "重命名失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    public func delete(takeID: UUID) -> Bool {
        guard let index = takes.firstIndex(where: { $0.id == takeID }) else { return false }
        do {
            var updated = takes
            updated.remove(at: index)
            try store.save(updated)
            takes = updated
            if selectedTakeID == takeID { selectedTakeID = nil }
            errorMessage = nil
            return true
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    public func clearAll() -> Bool {
        do {
            try store.save([])
            takes = []
            selectedTakeID = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = "清空失败：\(error.localizedDescription)"
            return false
        }
    }

    public func makeMIDIExport(for take: RecordingTake) throws -> RecordingMIDIExport {
        try midiExportService.makeMIDIExport(from: take)
    }

    public func dismissError() { errorMessage = nil }
}
