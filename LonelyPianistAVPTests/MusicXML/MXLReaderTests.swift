import Foundation
@testable import LonelyPianistAVP
import Testing
import ZIPFoundation

struct MXLReaderTests {
    @Test
    func readsScoreDataViaContainerRootfile() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "MXLReaderTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="score.xml" media-type="application/vnd.recordare.musicxml+xml"/>
          </rootfiles>
        </container>
        """

        let scoreXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>1</divisions></attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration>
                <type>quarter</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

        let metaInfURL = baseURL.appending(path: "META-INF")
        try FileManager.default.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try containerXML.data(using: .utf8)?.write(to: metaInfURL.appending(path: "container.xml"))
        try scoreXML.data(using: .utf8)?.write(to: baseURL.appending(path: "score.xml"))

        let mxlURL = baseURL.appending(path: "fixture.mxl")
        let archive = try Archive(url: mxlURL, accessMode: .create)

        try archive.addEntry(with: "META-INF/container.xml", relativeTo: baseURL, compressionMethod: .deflate)
        try archive.addEntry(with: "score.xml", relativeTo: baseURL, compressionMethod: .deflate)

        let reader = MXLReader()
        let data = try reader.readScoreXMLData(from: mxlURL)

        #expect(String(data: data, encoding: .utf8)?.contains("<score-partwise") == true)
    }

    @Test
    func throwsWhenContainerIsMissing() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "MXLReaderTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let scoreXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0"></score-partwise>
        """
        try scoreXML.data(using: .utf8)?.write(to: baseURL.appending(path: "score.xml"))

        let mxlURL = baseURL.appending(path: "fixture.mxl")
        let archive = try Archive(url: mxlURL, accessMode: .create)
        try archive.addEntry(with: "score.xml", relativeTo: baseURL, compressionMethod: .deflate)

        let reader = MXLReader()
        #expect(throws: MXLReaderError.missingContainerXML) {
            _ = try reader.readScoreXMLData(from: mxlURL)
        }
    }

    @Test
    func throwsWhenRootfileIsMissing() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "MXLReaderTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles></rootfiles>
        </container>
        """

        let metaInfURL = baseURL.appending(path: "META-INF")
        try FileManager.default.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try containerXML.data(using: .utf8)?.write(to: metaInfURL.appending(path: "container.xml"))

        let mxlURL = baseURL.appending(path: "fixture.mxl")
        let archive = try Archive(url: mxlURL, accessMode: .create)
        try archive.addEntry(with: "META-INF/container.xml", relativeTo: baseURL, compressionMethod: .deflate)

        let reader = MXLReader()
        #expect(throws: MXLReaderError.missingRootfileFullPath) {
            _ = try reader.readScoreXMLData(from: mxlURL)
        }
    }

    @Test
    func throwsWhenScoreXMLIsMissing() throws {
        let baseURL = FileManager.default.temporaryDirectory
            .appending(path: "MXLReaderTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseURL) }

        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="missing.xml" media-type="application/vnd.recordare.musicxml+xml"/>
          </rootfiles>
        </container>
        """

        let metaInfURL = baseURL.appending(path: "META-INF")
        try FileManager.default.createDirectory(at: metaInfURL, withIntermediateDirectories: true)
        try containerXML.data(using: .utf8)?.write(to: metaInfURL.appending(path: "container.xml"))

        let mxlURL = baseURL.appending(path: "fixture.mxl")
        let archive = try Archive(url: mxlURL, accessMode: .create)
        try archive.addEntry(with: "META-INF/container.xml", relativeTo: baseURL, compressionMethod: .deflate)

        let reader = MXLReader()
        #expect(throws: MXLReaderError.missingScoreXML(path: "missing.xml")) {
            _ = try reader.readScoreXMLData(from: mxlURL)
        }
    }
}
