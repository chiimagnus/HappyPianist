import Foundation
import ZIPFoundation

enum MXLReaderError: Error, Equatable {
    case invalidArchive
    case missingContainerXML
    case missingRootfileFullPath
    case missingScoreXML(path: String)
    case invalidContainerXML
}

struct MXLReader {
    func readScoreXMLData(from mxlFileURL: URL) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(url: mxlFileURL, accessMode: .read)
        } catch {
            throw MXLReaderError.invalidArchive
        }

        let containerPath = "META-INF/container.xml"
        guard let containerEntry = archive[containerPath] else {
            throw MXLReaderError.missingContainerXML
        }

        let containerData = try extract(entry: containerEntry, from: archive)
        let rootfileFullPath = try parseRootfileFullPath(fromContainerXML: containerData)

        let normalizedRootfilePath = rootfileFullPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let scoreEntry = archive[normalizedRootfilePath] else {
            throw MXLReaderError.missingScoreXML(path: rootfileFullPath)
        }

        return try extract(entry: scoreEntry, from: archive)
    }

    private func extract(entry: Entry, from archive: Archive) throws -> Data {
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    private func parseRootfileFullPath(fromContainerXML data: Data) throws -> String {
        let delegate = MXLContainerXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MXLReaderError.invalidContainerXML
        }
        guard let rootfileFullPath = delegate.rootfileFullPath, !rootfileFullPath.isEmpty else {
            throw MXLReaderError.missingRootfileFullPath
        }
        return rootfileFullPath
    }
}

private final class MXLContainerXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var rootfileFullPath: String?

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard rootfileFullPath == nil else { return }

        if elementName == "rootfile" || qName?.hasSuffix(":rootfile") == true {
            if let fullPath = attributeDict["full-path"] {
                rootfileFullPath = fullPath
            }
        }
    }
}
