//
//  ContentView.swift
//  LonelyPianistAVP
//
//  Created by chii_magnus on 2026/4/6.
//

import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isImporterPresented = false
    @State private var importedFile: ImportedMusicXMLFile?
    @State private var importedSteps: [PracticeStep] = []
    @State private var importErrorMessage: String?
    @State private var calibrationCaptureService = CalibrationPointCaptureService()
    @State private var calibrationStatusMessage: String?
    @State private var pendingCalibrationCaptureAnchor: CalibrationAnchorPoint?

    private let importService: MusicXMLImportServiceProtocol = MusicXMLImportService()
    private let calibrationStore: PianoCalibrationStoreProtocol = PianoCalibrationStore()
    private let parser: MusicXMLParserProtocol = MusicXMLParser()
    private let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
    private let keyGeometryService: PianoKeyGeometryServiceProtocol = PianoKeyGeometryService()

    var body: some View {
        RealityView { content in
            let tapTarget = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(10, 10, 10)),
                materials: [SimpleMaterial(color: .init(white: 1, alpha: 0), isMetallic: false)]
            )
            tapTarget.name = "TapTarget"
            tapTarget.components.set(InputTargetComponent())
            var collision = CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(10, 10, 10))])
            collision.filter = CollisionFilter(group: [], mask: [])
            tapTarget.components.set(collision)

            let anchor = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
            anchor.addChild(tapTarget)
            content.add(anchor)
        } update: { content in
            _ = content
        }
        .gesture(SpatialTapGesture(coordinateSpace3D: .worldReference).targetedToAnyEntity().onEnded { value in
            let point3D = value.location3D
            let point = SIMD3<Float>(Float(point3D.x), Float(point3D.y), Float(point3D.z))
            calibrationCaptureService.updateReticleEstimate(point)
            if let pendingCalibrationCaptureAnchor {
                calibrationCaptureService.capture(pendingCalibrationCaptureAnchor)
                calibrationStatusMessage = "Captured \(pendingCalibrationCaptureAnchor == .a0 ? "A0" : "C8")"
                self.pendingCalibrationCaptureAnchor = nil
            }
        })
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                VStack (spacing: 12) {
                    Button("Import MusicXML…") {
                        isImporterPresented = true
                    }

                    ToggleImmersiveSpaceButton()

                    if let importedFile {
                        Text("Imported: \(importedFile.fileName)")
                            .font(.caption)
                    }

                    if let importErrorMessage {
                        Text(importErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let pendingCalibrationCaptureAnchor {
                        Text("Tap to set: \(pendingCalibrationCaptureAnchor == .a0 ? "A0" : "C8")")
                            .font(.caption)
                    }

                    HStack(spacing: 8) {
                        Button("Set A0") {
                            pendingCalibrationCaptureAnchor = .a0
                        }
                        Button("Set C8") {
                            pendingCalibrationCaptureAnchor = .c8
                        }
                        Button("Save Calibration") {
                            saveCalibration()
                        }
                    }

                    Button("Use Manual Fallback") {
                        calibrationCaptureService.updateReticleEstimate(nil)
                    }

                    if calibrationCaptureService.mode == .manualFallback {
                        HStack(spacing: 8) {
                            Button("A0 ◀︎") {
                                calibrationCaptureService.adjust(anchor: .a0, delta: SIMD3<Float>(-0.01, 0, 0))
                            }
                            Button("A0 ▶︎") {
                                calibrationCaptureService.adjust(anchor: .a0, delta: SIMD3<Float>(0.01, 0, 0))
                            }
                            Button("C8 ◀︎") {
                                calibrationCaptureService.adjust(anchor: .c8, delta: SIMD3<Float>(-0.01, 0, 0))
                            }
                            Button("C8 ▶︎") {
                                calibrationCaptureService.adjust(anchor: .c8, delta: SIMD3<Float>(0.01, 0, 0))
                            }
                        }
                    }

                    if let calibrationStatusMessage {
                        Text(calibrationStatusMessage)
                            .font(.caption)
                    }

                    if let currentStep = appModel.practiceSessionViewModel.currentStep {
                        Text("Current Step: \(stepSummary(for: currentStep))")
                            .font(.caption)
                    }

                    HStack(spacing: 8) {
                        Button("Skip") {
                            appModel.practiceSessionViewModel.skip()
                        }
                        Button("Mark Correct") {
                            appModel.practiceSessionViewModel.markCorrect()
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .onAppear {
            calibrationCaptureService.updateReticleEstimate(SIMD3<Float>(0, 0.8, -1.0))
            loadStoredCalibrationIfPossible()
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else {
                return
            }
            let imported = try importService.importFile(from: selectedURL)
            importedFile = imported
            let score = try parser.parse(fileURL: imported.storedURL)
            let buildResult = stepBuilder.buildSteps(from: score)
            importedSteps = buildResult.steps
            if let calibration = try calibrationStore.load() {
                applySession(steps: importedSteps, calibration: calibration)
            } else {
                calibrationStatusMessage = "Imported score. Capture A0/C8 to start guiding."
            }
            importErrorMessage = nil
        } catch {
            importErrorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func saveCalibration() {
        do {
            guard let calibration = calibrationCaptureService.buildCalibration() else {
                calibrationStatusMessage = "Capture A0 and C8 first."
                return
            }
            try calibrationStore.save(calibration)
            calibrationStatusMessage = "Calibration saved."
            if importedSteps.isEmpty == false {
                applySession(steps: importedSteps, calibration: calibration)
            }
        } catch {
            calibrationStatusMessage = "Failed to save calibration: \(error.localizedDescription)"
        }
    }

    private func applySession(steps: [PracticeStep], calibration: PianoCalibration) {
        let regions = keyGeometryService.generateKeyRegions(from: calibration)
        appModel.practiceSessionViewModel.configure(steps: steps, calibration: calibration, keyRegions: regions)
        appModel.practiceSessionViewModel.startGuidingIfReady()
    }

    private func loadStoredCalibrationIfPossible() {
        do {
            guard let calibration = try calibrationStore.load() else { return }
            calibrationCaptureService.a0Point = calibration.a0.simdValue
            calibrationCaptureService.c8Point = calibration.c8.simdValue
            calibrationCaptureService.updateReticleEstimate(calibration.a0.simdValue)
            if importedSteps.isEmpty == false {
                applySession(steps: importedSteps, calibration: calibration)
            }
        } catch {
            calibrationStatusMessage = "Failed to load calibration: \(error.localizedDescription)"
        }
    }

    private func stepSummary(for step: PracticeStep) -> String {
        step.notes.map { midiToName($0.midiNote) }.joined(separator: " + ")
    }

    private func midiToName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = midi / 12 - 1
        let index = max(0, min(11, midi % 12))
        return "\(names[index])\(octave)"
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
