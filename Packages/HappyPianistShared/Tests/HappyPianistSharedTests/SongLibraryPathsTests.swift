import Foundation
import Testing
@testable import HappyPianistShared

@Test
func songLibraryPathsUseTheHostDocumentsDirectory() throws {
    let hostDocumentsDirectory = URL(filePath: "/tmp/happy-pianist-host-documents", directoryHint: .isDirectory)
    let paths = SongLibraryPaths(documentsDirectoryURL: hostDocumentsDirectory)

    #expect(
        try paths.rootDirectoryURL()
            == hostDocumentsDirectory.appending(path: SongLibraryLayout.rootDirectoryName, directoryHint: .isDirectory)
    )
}
