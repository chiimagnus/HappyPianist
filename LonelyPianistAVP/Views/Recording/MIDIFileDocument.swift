import SwiftUI
import UniformTypeIdentifiers

struct MIDIFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.midi] }
    static var writableContentTypes: [UTType] { [.midi] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
