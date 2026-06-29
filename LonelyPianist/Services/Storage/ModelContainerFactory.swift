import Foundation
import SwiftData

enum ModelContainerFactory {
    static func makeMainContainer() throws -> ModelContainer {
        let schema = Schema([
            RecordingTakeEntity.self,
            RecordedNoteEntity.self,
        ])
        let storeURL = try makeStoreURL()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            try deleteStoreFiles(at: storeURL)
            return try ModelContainer(for: schema, configurations: configuration)
        }
    }

    private static func makeStoreURL() throws -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.chiimagnus.LonelyPianist"
        let directory = URL.applicationSupportDirectory.appending(path: bundleID, directoryHint: .isDirectory)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "LonelyPianist.store")
    }

    private static func deleteStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-journal"),
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
