import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isImporterPresented = false

    private let importService: MusicXMLImportServiceProtocol = MusicXMLImportService()
    private let parser: MusicXMLParserProtocol = MusicXMLParser()
    private let stepBuilder: PracticeStepBuilderProtocol = PracticeStepBuilder()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LonelyPianist")
                .font(.largeTitle)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                Text("AR Guide")
                    .font(.headline)

                HStack(spacing: 12) {
                    ToggleImmersiveSpaceButton()

                    Text(appModel.immersiveSpaceState == .open ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(appModel.calibration == nil ? "Calibration: not set" : "Calibration: loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(nextActionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let calibrationStatusMessage = appModel.calibrationStatusMessage {
                    Text(calibrationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Score")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button("Import MusicXML…") {
                        isImporterPresented = true
                    }

                    if let importedFile = appModel.importedFile {
                        Text(importedFile.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No score imported")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let importErrorMessage = appModel.importErrorMessage {
                    Text(importErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if appModel.importedSteps.isEmpty == false {
                    Text("Steps: \(appModel.importedSteps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Practice")
                    .font(.headline)

                Text(practiceStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appModel.importedSteps.isEmpty == false {
                    HStack(spacing: 12) {
                        Button("Skip") { appModel.practiceSessionViewModel.skip() }
                            .disabled(appModel.immersiveSpaceState != .open)

                        Button("Mark Correct") { appModel.practiceSessionViewModel.markCorrect() }
                            .disabled(appModel.immersiveSpaceState != .open)
                    }
                } else {
                    Text("Import a score to enable step controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer()
        }
        .padding(24)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .onAppear {
            appModel.loadStoredCalibrationIfPossible()
        }
    }

    private var nextActionHint: String {
        if appModel.calibration == nil {
            return "Next: Enter AR Guide, then use the HUD buttons: Set A0 → Set C8 → Save."
        }
        if appModel.importedSteps.isEmpty {
            return "Next: Import MusicXML in this window."
        }
        return "Next: Enter AR Guide to see highlighted keys and start guiding."
    }

    private var practiceStatusText: String {
        switch appModel.practiceSessionViewModel.state {
        case .idle:
            return "Idle"
        case .ready:
            return "Ready (enter AR guide)"
        case .guiding(let index):
            return "Guiding (step \(index + 1))"
        case .completed:
            return "Completed"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else {
                return
            }
            let importedFile = try importService.importFile(from: selectedURL)
            let score = try parser.parse(fileURL: importedFile.storedURL)
            let buildResult = stepBuilder.buildSteps(from: score)
            if buildResult.unsupportedNoteCount > 0 {
                appModel.importErrorMessage = "Imported with \(buildResult.unsupportedNoteCount) unsupported notes ignored."
            }
            appModel.setImportedSteps(buildResult.steps, file: importedFile)
        } catch {
            appModel.importErrorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
