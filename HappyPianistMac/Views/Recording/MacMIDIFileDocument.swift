import SwiftUI
import UniformTypeIdentifiers

struct MacMIDIFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.midi] }
    static var writableContentTypes: [UTType] { [.midi] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
