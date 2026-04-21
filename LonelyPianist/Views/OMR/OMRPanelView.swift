import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OMRPanelView: View {
    @State private var isImporterPresented = false
    @State private var selectedInputURL: URL?
    @State private var outputMusicXMLURL: URL?
    @State private var statusMessage = "Select a score and convert to MusicXML."
    @State private var isConverting = false
    @State private var isPreviewPresented = false
    @State private var previewSVG: String?

    private let conversionService: OMRConversionServiceProtocol = OMRConversionService()
    private let renderService = VerovioMusicXMLRenderService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OMR Converter")
                .font(.title2.bold())

            Text("1. Choose a PDF/image  2. Click Convert  3. Open generated score.musicxml")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Select Score…") {
                    isImporterPresented = true
                }

                Button("Convert") {
                    convertSelectedFile()
                }
                .disabled(selectedInputURL == nil || isConverting)
            }

            if let selectedInputURL {
                Text("Input: \(selectedInputURL.path)")
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let outputMusicXMLURL {
                Text("Output: \(outputMusicXMLURL.path)")
                    .font(.callout)
                    .textSelection(.enabled)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([outputMusicXMLURL])
                }

                Button("Preview Sheet") {
                    renderPreview(from: outputMusicXMLURL)
                }
                .disabled(isConverting)
            }

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(isConverting ? .secondary : .primary)

            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $isPreviewPresented) {
            if let previewSVG {
                SheetMusicPreviewView(svg: previewSVG)
            } else {
                Text("No preview available.")
                    .padding(20)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: false
        ) { result in
            do {
                selectedInputURL = try result.get().first
                outputMusicXMLURL = nil
                statusMessage = "Ready to convert."
            } catch {
                statusMessage = "File selection failed: \(error.localizedDescription)"
            }
        }
    }

    private func convertSelectedFile() {
        guard let selectedInputURL else { return }
        isConverting = true
        statusMessage = "Converting..."
        Task {
            do {
                let output = try conversionService.convert(inputURL: selectedInputURL)
                await MainActor.run {
                    outputMusicXMLURL = output
                    statusMessage = "Convert succeeded."
                    isConverting = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Convert failed: \(error.localizedDescription)"
                    isConverting = false
                }
            }
        }
    }

    private func renderPreview(from musicXMLURL: URL) {
        statusMessage = "Rendering preview..."
        previewSVG = nil

        Task {
            do {
                let svg = try renderService.renderSVG(fileURL: musicXMLURL)
                await MainActor.run {
                    previewSVG = svg
                    statusMessage = "Preview ready."
                    isPreviewPresented = true
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Preview failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
