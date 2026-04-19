import Foundation

protocol WorldAnchorCalibrationStoreProtocol {
    func load() throws -> StoredWorldAnchorCalibration?
    func save(_ calibration: StoredWorldAnchorCalibration) throws
}

enum WorldAnchorCalibrationStoreError: Error {
    case documentsUnavailable
}

struct WorldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol {
    private let fileManager: FileManager
    private let fileName: String

    init(fileManager: FileManager = .default, fileName: String = "piano-worldanchor-calibration.json") {
        self.fileManager = fileManager
        self.fileName = fileName
    }

    func load() throws -> StoredWorldAnchorCalibration? {
        let fileURL = try calibrationFileURL()
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(StoredWorldAnchorCalibration.self, from: data)
    }

    func save(_ calibration: StoredWorldAnchorCalibration) throws {
        let fileURL = try calibrationFileURL()
        let data = try JSONEncoder().encode(calibration)
        try data.write(to: fileURL, options: .atomic)
    }

    private func calibrationFileURL() throws -> URL {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw WorldAnchorCalibrationStoreError.documentsUnavailable
        }
        return documents.appendingPathComponent(fileName)
    }
}
