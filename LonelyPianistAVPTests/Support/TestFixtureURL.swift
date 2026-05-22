import Foundation

func testFixtureURL(_ name: String, filePath: StaticString = #filePath) -> URL {
    var directory = URL(filePath: "\(filePath)").deletingLastPathComponent()
    while directory.lastPathComponent != "LonelyPianistAVPTests", directory.pathComponents.count > 1 {
        directory.deleteLastPathComponent()
    }
    return directory
        .appending(path: "Fixtures")
        .appending(path: name)
}

