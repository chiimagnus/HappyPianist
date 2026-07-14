import ARKit
import Foundation
import os
import simd

private let calibrationRepositoryLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "HappyPianistAVP",
    category: "CalibrationRepository"
)

protocol CalibrationRepositoryProtocol {
    func loadStoredCalibration() throws -> StoredWorldAnchorCalibration?
    func saveCalibration(
        a0AnchorID: UUID,
        c8AnchorID: UUID,
        whiteKeyWidth: Float
    ) throws -> StoredWorldAnchorCalibration
    @MainActor
    func removeOldAnchorsIfPossible(
        previous: StoredWorldAnchorCalibration,
        current: StoredWorldAnchorCalibration,
        arTrackingService: ARTrackingServiceProtocol
    ) async
    @MainActor
    func removeCapturedAnchorsIfPossible(
        _ anchorIDs: Set<UUID>,
        arTrackingService: ARTrackingServiceProtocol
    ) async
}

struct CalibrationRepository: CalibrationRepositoryProtocol {
    private let worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol

    init(worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol? = nil) {
        self.worldAnchorCalibrationStore = worldAnchorCalibrationStore ?? WorldAnchorCalibrationStore()
    }

    func loadStoredCalibration() throws -> StoredWorldAnchorCalibration? {
        try worldAnchorCalibrationStore.load()
    }

    func saveCalibration(
        a0AnchorID: UUID,
        c8AnchorID: UUID,
        whiteKeyWidth: Float
    ) throws -> StoredWorldAnchorCalibration {
        let calibration = StoredWorldAnchorCalibration(
            a0AnchorID: a0AnchorID,
            c8AnchorID: c8AnchorID,
            whiteKeyWidth: whiteKeyWidth
        )
        try worldAnchorCalibrationStore.save(calibration)
        return calibration
    }

    @MainActor
    func removeOldAnchorsIfPossible(
        previous: StoredWorldAnchorCalibration,
        current: StoredWorldAnchorCalibration,
        arTrackingService: ARTrackingServiceProtocol
    ) async {
        let oldIDs = Set([previous.a0AnchorID, previous.c8AnchorID])
        let currentIDs = Set([current.a0AnchorID, current.c8AnchorID])

        for oldID in oldIDs where currentIDs.contains(oldID) == false {
            do {
                try await arTrackingService.removeWorldAnchor(id: oldID)
            } catch {
                calibrationRepositoryLogger.error(
                    "删除旧锚点失败（UUID=\(oldID.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    @MainActor
    func removeCapturedAnchorsIfPossible(
        _ anchorIDs: Set<UUID>,
        arTrackingService: ARTrackingServiceProtocol
    ) async {
        for anchorID in anchorIDs {
            do {
                try await arTrackingService.removeWorldAnchor(id: anchorID)
            } catch {
                calibrationRepositoryLogger.error(
                    "删除临时校准锚点失败（UUID=\(anchorID.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
