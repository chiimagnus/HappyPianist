import SwiftUI
import UniformTypeIdentifiers

struct SheetMusicPanelView: View {
    @State private var isImporterPresented = false
    @State private var selectedMusicXMLURL: URL?
    @State private var statusMessage = "Select a MusicXML file to preview."
    @State private var isRendering = false

    @State private var isPreviewPresented = false
    @State private var previewSVG: String?

    private let renderService = VerovioMusicXMLRenderService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sheet Preview")
                .font(.title2.bold())

            Text("Choose a MusicXML (.musicxml/.xml) file and render it with Verovio.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Select MusicXML…") {
                    isImporterPresented = true
                }

                Button("Render Preview") {
                    renderPreview()
                }
                .disabled(selectedMusicXMLURL == nil || isRendering)
            }

            if let selectedMusicXMLURL {
                Text("Input: \(selectedMusicXMLURL.path)")
                    .font(.callout)
                    .textSelection(.enabled)
            }

            Text(statusMessage)
                .font(.callout)
                .foregroundStyle(isRendering ? .secondary : .primary)

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
            allowedContentTypes: [.xml, .musicXML],
            allowsMultipleSelection: false
        ) { result in
            do {
                selectedMusicXMLURL = try result.get().first
                previewSVG = nil
                statusMessage = "Ready to render."
            } catch {
                statusMessage = "File selection failed: \(error.localizedDescription)"
            }
        }
    }

    private func renderPreview() {
        guard let selectedMusicXMLURL else { return }
        isRendering = true
        statusMessage = "Rendering..."
        previewSVG = nil

        Task {
            do {
                let svg = try renderService.renderSVG(fileURL: selectedMusicXMLURL)
                await MainActor.run {
                    previewSVG = svg
                    statusMessage = "Preview ready."
                    isRendering = false
                    isPreviewPresented = true
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Render failed: \(error.localizedDescription)"
                    isRendering = false
                }
            }
        }
    }
}

extension UTType {
    static var musicXML: UTType {
        UTType(importedAs: "com.recordare.musicxml")
    }
}

