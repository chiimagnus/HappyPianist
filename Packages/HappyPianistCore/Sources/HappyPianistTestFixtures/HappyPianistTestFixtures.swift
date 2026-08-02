import Foundation

public enum HappyPianistTestFixtures {
    public static func url(named relativePath: String) -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        precondition(
            components.isEmpty == false && components.allSatisfy { $0.isEmpty == false && $0 != "." && $0 != ".." },
            "Fixture path must be a non-empty relative path."
        )
        guard let resourceURL = Bundle.module.resourceURL else {
            preconditionFailure("Test fixture bundle has no resource directory.")
        }
        return resourceURL
            .appending(path: "Fixtures", directoryHint: .isDirectory)
            .appending(path: relativePath)
    }
}
