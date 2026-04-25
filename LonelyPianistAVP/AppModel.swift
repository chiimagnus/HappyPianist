import ARKit
import simd
import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
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

    let practiceSessionViewModel: PracticeSessionViewModel
    let arTrackingService: ARTrackingServiceProtocol

    var importedFile: ImportedMusicXMLFile?
    var importedSteps: [PracticeStep] = []
    var importErrorMessage: String?

    var storedCalibration: StoredWorldAnchorCalibration?

    var calibration: PianoCalibration? {
        didSet { applySessionIfPossible() }
    }

    let calibrationCaptureService: CalibrationPointCaptureService
    var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint?
    var calibrationStatusMessage: String?

    private let worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol
    private let keyGeometryService: PianoKeyGeometryServiceProtocol
    private let importService: MusicXMLImportServiceProtocol
    private let parser: MusicXMLParserProtocol
    private let stepBuilder: PracticeStepBuilderProtocol
    private let structureExpander = MusicXMLStructureExpander()

    init(
        worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol? = nil,
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        importService: MusicXMLImportServiceProtocol? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil,
        practiceSessionViewModel: PracticeSessionViewModel? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil,
        calibrationCaptureService: CalibrationPointCaptureService? = nil
    ) {
        self.worldAnchorCalibrationStore = worldAnchorCalibrationStore ?? WorldAnchorCalibrationStore()
        self.keyGeometryService = keyGeometryService ?? PianoKeyGeometryService()
        self.importService = importService ?? MusicXMLImportService()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        self.practiceSessionViewModel = practiceSessionViewModel ?? PracticeSessionViewModel()
        self.arTrackingService = arTrackingService ?? ARTrackingService()
        self.calibrationCaptureService = calibrationCaptureService ?? CalibrationPointCaptureService()
    }

    func beginCalibrationRecapture() {
        let persistedAnchorIDs = Set([
            storedCalibration?.a0AnchorID,
            storedCalibration?.c8AnchorID
        ].compactMap(\.self))
        let capturedAnchorIDs = Set([
            calibrationCaptureService.a0AnchorID,
            calibrationCaptureService.c8AnchorID
        ].compactMap(\.self)).subtracting(persistedAnchorIDs)

        guard capturedAnchorIDs.isEmpty == false else {
            resetCalibrationCaptureState()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await removeCapturedAnchorsIfPossible(capturedAnchorIDs)
            resetCalibrationCaptureState()
        }
    }

    func setImportedSteps(
        _ steps: [PracticeStep],
        file: ImportedMusicXMLFile?,
        tempoMap: MusicXMLTempoMap? = nil,
        pedalTimeline: MusicXMLPedalTimeline? = nil,
        fermataTimeline: MusicXMLFermataTimeline? = nil,
        attributeTimeline: MusicXMLAttributeTimeline? = nil,
        slurTimeline: MusicXMLSlurTimeline? = nil,
        noteSpans: [MusicXMLNoteSpan] = []
    ) {
        importedSteps = steps
        importedFile = file
        importErrorMessage = nil
        practiceSessionViewModel.setSteps(
            steps,
            tempoMap: tempoMap,
            pedalTimeline: pedalTimeline,
            fermataTimeline: fermataTimeline,
            attributeTimeline: attributeTimeline,
            slurTimeline: slurTimeline,
            noteSpans: noteSpans
        )
        applySessionIfPossible()
    }

    func importMusicXML(from selectedURL: URL) {
        do {
            let importedFile = try importService.importFile(from: selectedURL)
            let score = try parser.parse(fileURL: importedFile.storedURL)
            let shouldExpandStructure = UserDefaults.standard.bool(forKey: "practiceMusicXMLStructureEnabled")
            let primaryPartIDForExpansion = score.preferredPrimaryPartID()
            let effectiveScore = shouldExpandStructure
                ? structureExpander.expandStructureIfPossible(score: score, primaryPartID: primaryPartIDForExpansion)
                : score
            let primaryPartID = effectiveScore.preferredPrimaryPartID(preferredPartID: primaryPartIDForExpansion)
            let practiceScore = effectiveScore.filtering(toPartID: primaryPartID)

            let expressivityOptions = MusicXMLExpressivityOptions(
                wedgeEnabled: UserDefaults.standard.bool(forKey: "practiceMusicXMLWedgeEnabled"),
                graceEnabled: UserDefaults.standard.bool(forKey: "practiceMusicXMLGraceEnabled"),
                fermataEnabled: UserDefaults.standard.bool(forKey: "practiceMusicXMLFermataEnabled"),
                arpeggiateEnabled: UserDefaults.standard.bool(forKey: "practiceMusicXMLArpeggiateEnabled"),
                wordsSemanticsEnabled: UserDefaults.standard.bool(forKey: "practiceMusicXMLWordsSemanticsEnabled")
            )
            let buildResult = stepBuilder.buildSteps(from: practiceScore, expressivity: expressivityOptions)
            let wordsSemantics = expressivityOptions.wordsSemanticsEnabled
                ? MusicXMLWordsSemanticsInterpreter().interpret(
                    wordsEvents: practiceScore.wordsEvents,
                    tempoEvents: practiceScore.tempoEvents
                )
                : nil
            let tempoMap = MusicXMLTempoMap(
                tempoEvents: practiceScore.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
                tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
                partID: primaryPartID
            )
            let pedalTimeline = MusicXMLPedalTimeline(events: practiceScore
                .pedalEvents + (wordsSemantics?.derivedPedalEvents ?? []))
            let fermataTimeline = expressivityOptions.fermataEnabled
                ? MusicXMLFermataTimeline(fermataEvents: practiceScore.fermataEvents, notes: practiceScore.notes)
                : nil
            let attributeTimeline = MusicXMLAttributeTimeline(
                timeSignatureEvents: practiceScore.timeSignatureEvents,
                keySignatureEvents: practiceScore.keySignatureEvents,
                clefEvents: practiceScore.clefEvents
            )
            let slurTimeline = MusicXMLSlurTimeline(events: practiceScore.slurEvents)
            let shouldUsePerformanceTiming = UserDefaults.standard
                .bool(forKey: "practiceMusicXMLPerformanceTimingEnabled")
            let noteSpans = MusicXMLNoteSpanBuilder().buildSpans(
                from: practiceScore.notes,
                performanceTimingEnabled: shouldUsePerformanceTiming,
                expressivity: expressivityOptions,
                fermataTimeline: fermataTimeline
            )
            if buildResult.unsupportedNoteCount > 0 {
                importErrorMessage = "已导入（忽略了 \(buildResult.unsupportedNoteCount) 个不支持的音符）。"
            } else {
                importErrorMessage = nil
            }
            setImportedSteps(
                buildResult.steps,
                file: importedFile,
                tempoMap: tempoMap,
                pedalTimeline: pedalTimeline,
                fermataTimeline: fermataTimeline,
                attributeTimeline: attributeTimeline,
                slurTimeline: slurTimeline,
                noteSpans: noteSpans
            )
        } catch {
            importErrorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func loadStoredCalibrationIfPossible() {
        do {
            guard let stored = try worldAnchorCalibrationStore.load() else { return }
            storedCalibration = stored
            calibrationStatusMessage = "已加载校准（待定位）"
        } catch {
            calibrationStatusMessage = "加载校准失败：\(error.localizedDescription)"
        }
    }

    func saveCalibrationIfPossible() {
        guard
            let a0AnchorID = calibrationCaptureService.a0AnchorID,
            let c8AnchorID = calibrationCaptureService.c8AnchorID,
            a0AnchorID != c8AnchorID
        else {
            calibrationStatusMessage = "校准信息不完整"
            return
        }

        let savedCalibration = StoredWorldAnchorCalibration(
            a0AnchorID: a0AnchorID,
            c8AnchorID: c8AnchorID,
            whiteKeyWidth: calibration?.whiteKeyWidth ?? storedCalibration?.whiteKeyWidth ?? 0.0235
        )
        let previousStoredCalibration = storedCalibration

        do {
            try worldAnchorCalibrationStore.save(savedCalibration)
            storedCalibration = savedCalibration
            calibration = nil
            pendingCalibrationCaptureAnchor = nil
            calibrationCaptureService.reset()
            calibrationStatusMessage = "已保存校准（待定位）"

            if let previousStoredCalibration {
                Task { @MainActor [weak self] in
                    await self?.removeOldAnchorsIfPossible(
                        previous: previousStoredCalibration,
                        current: savedCalibration
                    )
                }
            }
        } catch {
            calibrationStatusMessage = "保存校准失败：\(error.localizedDescription)"
        }
    }

    func clearRuntimeCalibrationForPracticeRelocation() {
        calibration = nil
        practiceSessionViewModel.clearCalibration()
    }

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

    private func removeOldAnchorsIfPossible(
        previous: StoredWorldAnchorCalibration,
        current: StoredWorldAnchorCalibration
    ) async {
        let oldIDs = Set([previous.a0AnchorID, previous.c8AnchorID])
        let currentIDs = Set([current.a0AnchorID, current.c8AnchorID])

        for oldID in oldIDs where currentIDs.contains(oldID) == false {
            guard let oldAnchor = arTrackingService.worldAnchorsByID[oldID] else {
                print("未在当前环境恢复该锚点，无法删除（UUID=\(oldID.uuidString)）")
                continue
            }

            do {
                try await arTrackingService.worldTrackingProvider.removeAnchor(oldAnchor)
            } catch {
                print("删除旧锚点失败（UUID=\(oldID.uuidString)）：\(error.localizedDescription)")
            }
        }
    }

    private func removeCapturedAnchorsIfPossible(_ anchorIDs: Set<UUID>) async {
        for anchorID in anchorIDs {
            guard let anchor = arTrackingService.worldAnchorsByID[anchorID] else {
                continue
            }

            do {
                try await arTrackingService.worldTrackingProvider.removeAnchor(anchor)
            } catch {
                print("删除临时校准锚点失败（UUID=\(anchorID.uuidString)）：\(error.localizedDescription)")
            }
        }
    }

    private func resetCalibrationCaptureState() {
        pendingCalibrationCaptureAnchor = nil
        calibrationStatusMessage = "请重新校准"
        calibration = nil
        calibrationCaptureService.reset()
        practiceSessionViewModel.resetSession()
    }

    private func applySessionIfPossible() {
        guard let calibration else { return }
        guard let keyboardGeometry = keyGeometryService.generateKeyboardGeometry(from: calibration) else { return }
        practiceSessionViewModel.applyKeyboardGeometry(keyboardGeometry, calibration: calibration)
    }

    private func worldAnchorPoint(from anchor: WorldAnchor) -> SIMD3<Float> {
        let transform = anchor.originFromAnchorTransform
        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
}
