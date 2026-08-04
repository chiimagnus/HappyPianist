import Foundation

import ZIPFoundation

public enum MXLReaderError: Error, Equatable {
    case invalidArchive
    case rejectedBySafetyPolicy(MusicXMLImportSafetyRejection)
    case missingContainerXML
    case missingRootfileFullPath
    case missingScoreXML(path: String)
    case invalidContainerXML
}

extension MXLReaderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "无效的 .mxl 压缩包（可能已损坏或无法读取）"
        case .rejectedBySafetyPolicy:
            "这份 .mxl 文件不符合安全导入限制。"
        case .missingContainerXML:
            "无效的 .mxl：缺少 META-INF/container.xml"
        case .missingRootfileFullPath:
            "无效的 .mxl：container.xml 缺少 rootfile full-path"
        case let .missingScoreXML(path):
            "无效的 .mxl：未找到谱面文件（\(path)）"
        case .invalidContainerXML:
            "无效的 .mxl：container.xml 不是有效的 XML"
        }
    }
}

public struct MXLReader {
    private let safetyValidator: MusicXMLImportSafetyValidator

    public init(safetyPolicy: MusicXMLImportSafetyPolicy = .init()) {
        safetyValidator = MusicXMLImportSafetyValidator(policy: safetyPolicy)
    }

    public func readScoreXMLData(from mxlFileURL: URL) throws -> Data {
        do {
            try safetyValidator.validateRegularFile(at: mxlFileURL)
        } catch let rejection as MusicXMLImportSafetyRejection {
            throw MXLReaderError.rejectedBySafetyPolicy(rejection)
        }
        let archive: Archive
        do {
            archive = try Archive(url: mxlFileURL, accessMode: .read)
        } catch {
            throw MXLReaderError.invalidArchive
        }
        do {
            try safetyValidator.validateArchive(archive)
        } catch let rejection as MusicXMLImportSafetyRejection {
            throw MXLReaderError.rejectedBySafetyPolicy(rejection)
        }

        let containerPath = "META-INF/container.xml"
        guard let containerEntry = archive[containerPath] else {
            throw MXLReaderError.missingContainerXML
        }

        let containerData = try extractSafely(entry: containerEntry, from: archive)
        let rootfileFullPath = try parseRootfileFullPath(fromContainerXML: containerData)

        let normalizedRootfilePath: String
        do {
            normalizedRootfilePath = try safetyValidator.normalizedArchivePath(rootfileFullPath)
        } catch let rejection as MusicXMLImportSafetyRejection {
            throw MXLReaderError.rejectedBySafetyPolicy(rejection)
        }
        guard let scoreEntry = archive[normalizedRootfilePath] else {
            throw MXLReaderError.missingScoreXML(path: rootfileFullPath)
        }

        return try extractSafely(entry: scoreEntry, from: archive)
    }

    private func extractSafely(entry: Entry, from archive: Archive) throws -> Data {
        do {
            try safetyValidator.validateExtractableEntry(entry)
        } catch let rejection as MusicXMLImportSafetyRejection {
            throw MXLReaderError.rejectedBySafetyPolicy(rejection)
        }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                guard Int64(data.count + chunk.count) <= safetyValidator.policy.maximumEntryUncompressedBytes else {
                    throw MusicXMLImportSafetyRejection.archiveEntryIsTooLarge
                }
                data.append(chunk)
            }
        } catch let rejection as MusicXMLImportSafetyRejection {
            throw MXLReaderError.rejectedBySafetyPolicy(rejection)
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

    public func parser(
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
