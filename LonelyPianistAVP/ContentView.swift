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

struct ContentView: View {

    @State private var enlarge = false
    @State private var isImporterPresented = false
    @State private var importedFile: ImportedMusicXMLFile?
    @State private var importErrorMessage: String?

    private let importService: MusicXMLImportServiceProtocol = MusicXMLImportService()

    var body: some View {
        RealityView { content in
            // Add the initial RealityKit content
            if let scene = try? await Entity(named: "Scene", in: realityKitContentBundle) {
                content.add(scene)
            }
        } update: { content in
            // Update the RealityKit content when SwiftUI state changes
            if let scene = content.entities.first {
                let uniformScale: Float = enlarge ? 1.4 : 1.0
                scene.transform.scale = [uniformScale, uniformScale, uniformScale]
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { _ in
            enlarge.toggle()
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
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let selectedURL = try result.get().first else {
                return
            }
            importedFile = try importService.importFile(from: selectedURL)
            importErrorMessage = nil
        } catch {
            importErrorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
