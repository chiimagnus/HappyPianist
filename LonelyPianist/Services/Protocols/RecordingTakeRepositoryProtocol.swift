import Foundation

@MainActor
protocol RecordingTakeRepositoryProtocol {
    func fetchTakes() throws -> [RecordingTake]
    func saveTake(_ take: RecordingTake) throws
    func deleteTake(id: UUID) throws
    func renameTake(id: UUID, name: String) throws
}
