import Foundation

enum LegacyPointCalibrationCleanup {
    static let legacyFileName = "piano-calibration.json"

    static func removeLegacyFileIfExists(fileManager: FileManager = .default) {
        guard let fileURL = legacyFileURL(fileManager: fileManager) else { return }
        guard fileManager.fileExists(atPath: fileURL.path()) else { return }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            print("删除旧版点位校准文件失败（\(legacyFileName)）：\(error.localizedDescription)")
        }
    }

    private static func legacyFileURL(fileManager: FileManager) -> URL? {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documents.appendingPathComponent(legacyFileName)
    }
}
