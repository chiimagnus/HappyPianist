import Foundation
import VerovioToolkit

enum VerovioMusicXMLRenderError: Error {
    case missingResourceBundle
    case loadFailed
    case invalidEncoding
}

struct VerovioMusicXMLRenderService {
    func renderSVG(fileURL: URL, page: Int = 1) throws -> String {
        let hasScopedAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        guard let xml = String(data: data, encoding: .utf8) else {
            throw VerovioMusicXMLRenderError.invalidEncoding
        }
        return try renderSVG(musicXML: xml, page: page)
    }

    func renderSVG(musicXML: String, page: Int = 1) throws -> String {
        let toolkit = VerovioToolkit()

        guard let dataURL = VerovioResources.bundle.url(forResource: "data", withExtension: nil) else {
            throw VerovioMusicXMLRenderError.missingResourceBundle
        }

        let dataDir = dataURL.deletingLastPathComponent().path + "/data"
        _ = toolkit.setResourcePath(dataDir)

        guard toolkit.loadData(musicXML) else {
            throw VerovioMusicXMLRenderError.loadFailed
        }

        return toolkit.renderToSVG(page, false)
    }
}
