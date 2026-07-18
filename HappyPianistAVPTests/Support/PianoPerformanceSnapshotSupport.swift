import Foundation
import Testing

struct PianoPerformanceSnapshotEncoder {
  private let locale = Locale(identifier: "en_US_POSIX")

  func encode(lines: [String]) -> String {
    lines.joined(separator: "\n") + "\n"
  }

  func encode(fields: [(String, String?)]) -> String {
    fields
      .map { key, value in "\(key)=\(value ?? "null")" }
      .joined(separator: "|")
  }

  func encode(_ value: Double) -> String {
    value.formatted(
      .number
        .locale(locale)
        .precision(.fractionLength(0...6))
        .grouping(.never)
    )
  }

  func encode<T: BinaryInteger>(_ value: T?) -> String {
    guard let value else { return "null" }
    return String(value)
  }

  func encode(_ value: Bool?) -> String {
    value.map { $0 ? "true" : "false" } ?? "null"
  }

  func encode(_ value: String?) -> String {
    value ?? "null"
  }
}

struct PianoPerformanceSnapshotDifference: Equatable, CustomStringConvertible {
  let line: Int
  let expected: String?
  let actual: String?

  var description: String {
    "line \(line): expected <\(expected ?? "end-of-snapshot")>, actual <\(actual ?? "end-of-snapshot")>"
  }
}

func firstSnapshotDifference(
  expected: String,
  actual: String
) -> PianoPerformanceSnapshotDifference? {
  let expectedLines = snapshotLines(expected)
  let actualLines = snapshotLines(actual)
  let count = max(expectedLines.count, actualLines.count)

  for index in 0..<count {
    let expectedLine = expectedLines.indices.contains(index) ? expectedLines[index] : nil
    let actualLine = actualLines.indices.contains(index) ? actualLines[index] : nil
    if expectedLine != actualLine {
      return PianoPerformanceSnapshotDifference(
        line: index + 1,
        expected: expectedLine,
        actual: actualLine
      )
    }
  }

  return nil
}

private func snapshotLines(_ snapshot: String) -> [String] {
  var lines = snapshot.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  if lines.last == "" {
    lines.removeLast()
  }
  return lines
}

@Test
func snapshotComparisonIgnoresOnlyTheTerminatingNewline() {
  #expect(firstSnapshotDifference(expected: "line", actual: "line\n") == nil)
  #expect(firstSnapshotDifference(expected: "line", actual: "line\n\n") != nil)
}

func expectSnapshot(
  _ actual: String,
  equals expected: String,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  if let difference = firstSnapshotDifference(expected: expected, actual: actual) {
    Issue.record("Snapshot mismatch: \(difference)", sourceLocation: sourceLocation)
  }
}
