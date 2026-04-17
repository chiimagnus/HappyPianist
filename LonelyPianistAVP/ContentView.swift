//
//  ContentView.swift
//  LonelyPianistAVP
//
//  Created by chii_magnus on 2026/4/6.
//

import SwiftUI
import RealityKit
import RealityKitContent
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var enlarge = false
    @State private var isImporterPresented = false
    @State private var importedFile: ImportedMusicXMLFile?
    @State private var importedSteps: [PracticeStep] = []
    @State private var importErrorMessage: String?
    @State private var calibrationCaptureService = CalibrationPointCaptureService()
    @State private var calibrationStatusMessage: String?

    private let importService: MusicXMLImportServiceProtocol = MusicXMLImportService()
    private let calibrationStore: PianoCalibrationStoreProtocol = PianoCalibrationStore()
    private let parser: MusicXMLParserProtocol = MusicXMLParser()
    private let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()
    private let keyGeometryService: PianoKeyGeometryServiceProtocol = PianoKeyGeometryService()

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let scene = try? await Entity(named: "Scene", in: realityKitContentBundle) {
                scene.name = "RootScene"
                scene.generateCollisionShapes(recursive: true)
                content.add(scene)
            }

            let reticle = ModelEntity(
                mesh: .generateSphere(radius: 0.008),
                materials: [SimpleMaterial(color: UIColor.systemYellow.withAlphaComponent(0.8), isMetallic: false)]
            )
            reticle.name = "CalibrationReticle"
            reticle.position = calibrationCaptureService.reticlePoint
            content.add(reticle)
        } update: { content in
            // Update the RealityKit content when SwiftUI state changes
            if let scene = content.entities.first(where: { $0.name == "RootScene" }) {
                let uniformScale: Float = enlarge ? 1.4 : 1.0
                scene.transform.scale = [uniformScale, uniformScale, uniformScale]
            }

            if let reticle = content.entities.first(where: { $0.name == "CalibrationReticle" }) as? ModelEntity {
                reticle.position = calibrationCaptureService.reticlePoint
            }
        }
        .gesture(SpatialTapGesture(coordinateSpace3D: .worldReference).targetedToAnyEntity().onEnded { value in
            let point3D = value.location3D
            let point = SIMD3<Float>(Float(point3D.x), Float(point3D.y), Float(point3D.z))
            calibrationCaptureService.updateReticleEstimate(point)
        })
        .toolbar {
            ToolbarItemGroup(placement: .bottomOrnament) {
                VStack (spacing: 12) {
                    Button("Import MusicXML…") {
                        isImporterPresented = true
                    }

                    Button {
                        enlarge.toggle()
                    } label: {
                        Text(enlarge ? "Reduce RealityView Content" : "Enlarge RealityView Content")
                    }
                    .animation(.none, value: 0)
                    .fontWeight(.semibold)

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

                    Text("Calibration mode: \(calibrationCaptureService.mode == .raycast ? "Raycast" : "Manual Fallback")")
                        .font(.caption)

                    HStack(spacing: 8) {
                        Button("Capture A0") {
                            calibrationCaptureService.capture(.a0)
                        }
                        Button("Capture C8") {
                            calibrationCaptureService.capture(.c8)
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
