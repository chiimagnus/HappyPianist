import ARKit
import Observation
import simd

/// Maintains app-wide state
@MainActor
@Observable
class AppState {
    enum PracticeCalibrationResolutionResult: Equatable {
        case resolved
        case missingStoredCalibration
        case anchorMissing(id: UUID)
        case anchorNotTracked(id: UUID)
        case anchorsTooClose(distanceMeters: Float)
        case devicePoseUnavailable
    }

    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    enum ImmersiveMode {
        case calibration
        case practice
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var immersiveMode: ImmersiveMode = .practice

    let arTrackingService: ARTrackingServiceProtocol

    var importedFile: ImportedMusicXMLFile?
    var importedSteps: [PracticeStep] = []
    var importErrorMessage: String?

    var storedCalibration: StoredWorldAnchorCalibration?

    /// Cached placement for the "virtual piano" mode (not the real-piano calibration flow).
    /// This is kept app-wide so users don't need to re-place it for each song's Step 3.
    var cachedVirtualPianoWorldFromKeyboard: simd_float4x4?

    var calibration: PianoCalibration? {
        didSet { applySessionIfPossible() }
    }

    let calibrationCaptureService: CalibrationPointCaptureService
    var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint?
    var calibrationStatusMessage: String?

    private let calibrationRepository: CalibrationRepositoryProtocol
    private let keyGeometryService: PianoKeyGeometryServiceProtocol
    private let importService: MusicXMLImportServiceProtocol
    private let practicePreparationService: PracticePreparationServiceProtocol

    init(
        arTrackingService: ARTrackingServiceProtocol,
        calibrationCaptureService: CalibrationPointCaptureService,
        calibrationRepository: CalibrationRepositoryProtocol,
        keyGeometryService: PianoKeyGeometryServiceProtocol,
        importService: MusicXMLImportServiceProtocol,
        practicePreparationService: PracticePreparationServiceProtocol
    ) {
        self.arTrackingService = arTrackingService
        self.calibrationCaptureService = calibrationCaptureService
        self.calibrationRepository = calibrationRepository
        self.keyGeometryService = keyGeometryService
        self.importService = importService
        self.practicePreparationService = practicePreparationService
    }

    /// Convenience init for tests/previews that don't need to control service instances.
    convenience init(
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil
    ) {
        self.init(
            arTrackingService: arTrackingService ?? ARTrackingService(),
            calibrationCaptureService: CalibrationPointCaptureService(),
            calibrationRepository: CalibrationRepository(),
            keyGeometryService: keyGeometryService ?? PianoKeyGeometryService(),
            importService: MusicXMLImportService(),
            practicePreparationService: PracticePreparationService()
        )
    }

    func beginCalibrationRecapture() {
        let persistedAnchorIDs = Set([
            storedCalibration?.a0AnchorID,
            storedCalibration?.c8AnchorID,
        ].compactMap(\.self))
        let capturedAnchorIDs = Set([
            calibrationCaptureService.a0AnchorID,
            calibrationCaptureService.c8AnchorID,
        ].compactMap(\.self)).subtracting(persistedAnchorIDs)

        guard capturedAnchorIDs.isEmpty == false else {
            resetCalibrationCaptureState()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await calibrationRepository.removeCapturedAnchorsIfPossible(
                capturedAnchorIDs,
                arTrackingService: arTrackingService
            )
            resetCalibrationCaptureState()
        }
    }

    func setImportedSteps(from prepared: PreparedPractice) {
        importedSteps = prepared.steps
        importedFile = prepared.file
        importErrorMessage = nil
        onStepsImported?(prepared)
    }

    var onStepsImported: ((PreparedPractice) -> Void)?

    func importMusicXML(from selectedURL: URL) {
        do {
            let importedFile = try importService.importFile(from: selectedURL)
            let prepared = try practicePreparationService.prepare(from: importedFile.storedURL, file: importedFile)
            if prepared.unsupportedNoteCount > 0 {
                importErrorMessage = "已导入（忽略了 \(prepared.unsupportedNoteCount) 个不支持的音符）。"
            } else {
                importErrorMessage = nil
            }
            setImportedSteps(from: prepared)
        } catch {
            importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func loadStoredCalibrationIfPossible() {
        do {
            guard let stored = try calibrationRepository.loadStoredCalibration() else { return }
            storedCalibration = stored
            calibrationStatusMessage = "已加载校准（待定位）"
        } catch {
            calibrationStatusMessage = "加载校准失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveCalibrationIfPossible() -> Bool {
        guard
            let a0AnchorID = calibrationCaptureService.a0AnchorID,
            let c8AnchorID = calibrationCaptureService.c8AnchorID,
            a0AnchorID != c8AnchorID
        else {
            calibrationStatusMessage = "校准信息不完整"
            return false
        }

        let previousStoredCalibration = storedCalibration

        do {
            let savedCalibration = try calibrationRepository.saveCalibration(
                a0AnchorID: a0AnchorID,
                c8AnchorID: c8AnchorID,
                whiteKeyWidth: calibration?.whiteKeyWidth ?? storedCalibration?.whiteKeyWidth ?? 0.0235
            )
            storedCalibration = savedCalibration
            calibration = nil
            pendingCalibrationCaptureAnchor = nil
            calibrationCaptureService.reset()
            calibrationStatusMessage = "已保存校准（待定位）"

            if let previousStoredCalibration {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.calibrationRepository.removeOldAnchorsIfPossible(
                        previous: previousStoredCalibration,
                        current: savedCalibration,
                        arTrackingService: self.arTrackingService
                    )
                }
            }
            return true
        } catch {
            calibrationStatusMessage = "保存校准失败：\(error.localizedDescription)"
            return false
        }
    }

    func clearRuntimeCalibrationForPracticeRelocation() {
        calibration = nil
        onCalibrationCleared?()
    }

    var onCalibrationCleared: (() -> Void)?

    func resolveRuntimeCalibrationFromTrackedAnchors() -> PracticeCalibrationResolutionResult {
        guard let storedCalibration else {
            return .missingStoredCalibration
        }

        guard let a0Anchor = arTrackingService.worldAnchorsByID[storedCalibration.a0AnchorID] else {
            return .anchorMissing(id: storedCalibration.a0AnchorID)
        }

        guard let c8Anchor = arTrackingService.worldAnchorsByID[storedCalibration.c8AnchorID] else {
            return .anchorMissing(id: storedCalibration.c8AnchorID)
        }

        guard a0Anchor.isTracked else {
            return .anchorNotTracked(id: storedCalibration.a0AnchorID)
        }

        guard c8Anchor.isTracked else {
            return .anchorNotTracked(id: storedCalibration.c8AnchorID)
        }

        let a0Point = worldAnchorPoint(from: a0Anchor)
        let c8Point = worldAnchorPoint(from: c8Anchor)

        let distanceMeters = simd_length(c8Point - a0Point)
        guard distanceMeters > 0.05 else {
            return .anchorsTooClose(distanceMeters: distanceMeters)
        }

        let planeY = (a0Point.y + c8Point.y) / 2

        // Interpret calibrated A0/C8 as the keyboard's *front edge line* (keyboard-local z = 0).
        // We still need to place highlights and hit regions at key centers, which are offset by
        // ±keyDepth/2 along the keyboard-local Z axis. Determine the correct sign using the current
        // device pose (which side the user is on).
        let frontEdgeToKeyCenterLocalZ: Float
        if let frame = KeyboardFrame(a0World: a0Point, c8World: c8Point, planeHeight: planeY) {
            let timestamp = ProcessInfo.processInfo.systemUptime
            guard
                let deviceAnchor = arTrackingService.worldTrackingProvider.queryDeviceAnchor(atTimestamp: timestamp),
                deviceAnchor.isTracked
            else {
                return .devicePoseUnavailable
            }

            let deviceTransform = deviceAnchor.originFromAnchorTransform
            let devicePos = SIMD3<Float>(
                deviceTransform.columns.3.x,
                deviceTransform.columns.3.y,
                deviceTransform.columns.3.z
            )

            let origin = frame.originWorld
            let toDevice = SIMD3<Float>(devicePos.x - origin.x, 0, devicePos.z - origin.z)
            let toDeviceLen = simd_length(toDevice)
            if toDeviceLen > 1e-4 {
                let toDeviceDir = toDevice / toDeviceLen
                let zAxis = frame.zAxisWorld
                // If the device is on +Z side, keyboard interior is -Z; otherwise interior is +Z.
                let interiorIsNegativeZ = simd_dot(toDeviceDir, zAxis) > 0
                frontEdgeToKeyCenterLocalZ = (interiorIsNegativeZ ? -1 : 1) *
                    (PianoKeyGeometryService.whiteKeyDepthMeters / 2)
            } else {
                // Degenerate; fall back to "no offset" rather than guessing a direction.
                frontEdgeToKeyCenterLocalZ = 0
            }
        } else {
            frontEdgeToKeyCenterLocalZ = 0
        }

        calibration = PianoCalibration(
            a0: a0Point,
            c8: c8Point,
            planeHeight: planeY,
            whiteKeyWidth: storedCalibration.whiteKeyWidth,
            frontEdgeToKeyCenterLocalZ: frontEdgeToKeyCenterLocalZ
        )

        return .resolved
    }

    private func resetCalibrationCaptureState() {
        pendingCalibrationCaptureAnchor = nil
        calibrationStatusMessage = "请重新校准"
        calibration = nil
        calibrationCaptureService.reset()
        onSessionReset?()
    }

    var onSessionReset: (() -> Void)?

    func applySessionIfPossible() {
        guard let calibration else { return }
        guard let keyboardGeometry = keyGeometryService.generateKeyboardGeometry(from: calibration) else { return }
        onApplyKeyboardGeometry?(keyboardGeometry, calibration)
    }

    var onApplyKeyboardGeometry: ((PianoKeyboardGeometry, PianoCalibration) -> Void)?

    private func worldAnchorPoint(from anchor: WorldAnchor) -> SIMD3<Float> {
        let transform = anchor.originFromAnchorTransform
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
}
