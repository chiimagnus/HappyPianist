import ARKit
import Foundation
import simd

protocol CalibrationRepositoryProtocol {
    func loadStoredCalibration() throws -> StoredWorldAnchorCalibration?
    func saveCalibration(
        a0AnchorID: UUID,
        c8AnchorID: UUID,
        whiteKeyWidth: Float,
        touchCalibration: PianoTouchCalibration
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
    private let diagnosticsReporter: (any DiagnosticsReporting)?

    init(
        worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol? = nil,
        diagnosticsReporter: (any DiagnosticsReporting)? = nil
    ) {
        self.worldAnchorCalibrationStore = worldAnchorCalibrationStore ?? WorldAnchorCalibrationStore()
        self.diagnosticsReporter = diagnosticsReporter
    }

    func loadStoredCalibration() throws -> StoredWorldAnchorCalibration? {
        try worldAnchorCalibrationStore.load()
    }

    func saveCalibration(
        a0AnchorID: UUID,
        c8AnchorID: UUID,
        whiteKeyWidth: Float,
        touchCalibration: PianoTouchCalibration
    ) throws -> StoredWorldAnchorCalibration {
        let calibration = StoredWorldAnchorCalibration(
            a0AnchorID: a0AnchorID,
            c8AnchorID: c8AnchorID,
            whiteKeyWidth: whiteKeyWidth,
            touchCalibration: touchCalibration
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
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .immersiveSpace,
                    stage: "calibration.removeOldAnchor",
                    summary: "删除旧校准锚点失败",
                    reason: "anchorID=\(oldID.uuidString), error=\(error.localizedDescription)"
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
                diagnosticsReporter?.recordSystem(
                    severity: .error,
                    category: .immersiveSpace,
                    stage: "calibration.removeCapturedAnchor",
                    summary: "删除临时校准锚点失败",
                    reason: "anchorID=\(anchorID.uuidString), error=\(error.localizedDescription)"
                )
            }
        }
    }
}
