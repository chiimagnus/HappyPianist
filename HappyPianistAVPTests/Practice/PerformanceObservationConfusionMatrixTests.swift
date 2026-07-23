import Foundation
import simd
@testable import HappyPianistAVP
import Testing

@Test
func performanceObservationReplayConfusionMatrixMatchesCapabilityScopedExpectations() throws {
    let replay = try PerformanceObservationReplayFixtureLoader().load()
    let document = try JSONDecoder().decode(
        ReplayConfusionMatrixDocument.self,
        from: Data(contentsOf: testFixtureURL("PerformanceObservationReplays.json"))
    )
    try requireMatrix(document.confusionMatrix.schemaVersion == 1, caseID: "observation-schema", detail: "unsupported matrix schema")
    let observationsByID = Dictionary(uniqueKeysWithValues: replay.observations.map { ($0.id.uuidString, $0) })

    for matrixCase in document.confusionMatrix.cases {
        try requireMatrix(matrixCase.rationale.isEmpty == false, caseID: matrixCase.id, detail: "missing threshold rationale")
        let observations = try matrixCase.observationIDs.map { id in
            guard let observation = observationsByID[id] else {
                throw PerformanceObservationMatrixError.violation(
                    caseID: matrixCase.id,
                    detail: "missing replay observation \(id)"
                )
            }
            return observation
        }
        try requireMatrix(
            observations.allSatisfy { matrixCase.capability.matches($0.source.capabilities.pitch) },
            caseID: matrixCase.id,
            detail: "pitch capability does not match \(matrixCase.capability.rawValue)"
        )
        try requireMatrix(
            observations.allSatisfy { $0.calibrationReference == matrixCase.calibrationVersion },
            caseID: matrixCase.id,
            detail: "calibration version does not match \(matrixCase.calibrationVersion)"
        )

        let actual: ConfusionCounts
        switch matrixCase.source {
        case .midi:
            try requireMatrix(
                observations.allSatisfy { $0.source.kind == .midi1 || $0.source.kind == .midi2 },
                caseID: matrixCase.id,
                detail: "non-MIDI observation entered MIDI matrix"
            )
            actual = confusionCounts(
                expected: matrixCase.expectedMIDINotes,
                detected: observations.compactMap { observation in
                    guard case let .noteOn(note, _) = observation.event else { return nil }
                    return note
                }
            )

        case .targetAudio:
            try requireMatrix(
                observations.count == 1 && observations.first?.source.kind == .targetAudio,
                caseID: matrixCase.id,
                detail: "target-audio matrix requires one target-audio observation"
            )
            guard case let .targetAudioDetection(target, detected, result) = observations[0].event else {
                throw PerformanceObservationMatrixError.violation(
                    caseID: matrixCase.id,
                    detail: "target-audio observation has the wrong event kind"
                )
            }
            try requireMatrix(
                target == matrixCase.expectedMIDINotes,
                caseID: matrixCase.id,
                detail: "target notes differ from the reviewed expectation"
            )
            actual = confusionCounts(
                expected: target,
                detected: detected,
                ambiguous: result == .mixed ? 1 : 0,
                insufficient: result == .unknown ? 1 : 0
            )
        }
        try assertMatrix(actual, equals: matrixCase.expected, caseID: matrixCase.id)
    }
}

@Test
@MainActor
func syntheticHandReplayConfusionMatrixPreservesInsufficientEvidence() throws {
    let fixture = try SyntheticHandContactTraceFixtureLoader().load()
    let document = try JSONDecoder().decode(
        HandConfusionMatrixDocument.self,
        from: Data(contentsOf: testFixtureURL("SyntheticHandContactTraces.json"))
    )
    try requireMatrix(document.confusionMatrix.schemaVersion == 1, caseID: "hand-schema", detail: "unsupported matrix schema")
    let keyboardGeometry = try #require(
        VirtualPianoKeyGeometryService().generateKeyboardGeometry(
            from: KeyboardFrame(worldFromKeyboard: matrix_identity_float4x4)
        )
    )
    let tracesByID = Dictionary(uniqueKeysWithValues: fixture.traces.map { ($0.id, $0) })

    for matrixCase in document.confusionMatrix.cases {
        try requireMatrix(matrixCase.rationale.isEmpty == false, caseID: matrixCase.id, detail: "missing threshold rationale")
        try requireMatrix(
            matrixCase.calibrationVersion == fixture.calibration.version,
            caseID: matrixCase.id,
            detail: "fixture calibration version changed from \(matrixCase.calibrationVersion)"
        )
        try requireMatrix(
            matrixCase.capability.matches(PerformanceInputCapabilities.handContact.pitch),
            caseID: matrixCase.id,
            detail: "hand pitch capability does not match \(matrixCase.capability.rawValue)"
        )

        var detected: [Int] = []
        for traceID in matrixCase.traceIDs {
            guard let trace = tracesByID[traceID] else {
                throw PerformanceObservationMatrixError.violation(
                    caseID: matrixCase.id,
                    detail: "missing hand trace \(traceID)"
                )
            }
            let detector = KeyContactDetectionService(calibration: fixture.calibration)
            let adapter = PianoKeyContactPerformanceObservationAdapter()
            for frame in trace.frames {
                let contacts = detector.detect(
                    fingerTips: try frame.snapshot(keyboardGeometry: keyboardGeometry),
                    keyboardGeometry: keyboardGeometry,
                    at: .init(seconds: frame.seconds)
                )
                for contact in contacts {
                    let observation = adapter.observation(
                        from: contact,
                        sourceKind: .virtualPianoContact,
                        generation: 1
                    )
                    try requireMatrix(
                        matrixCase.capability.matches(observation.source.capabilities.pitch),
                        caseID: matrixCase.id,
                        detail: "contact observation capability drifted"
                    )
                    if case let .contact(_, keyCandidate, .started) = observation.event, let keyCandidate {
                        detected.append(keyCandidate)
                    }
                }
            }
        }

        let actual = matrixCase.insufficient
            ? ConfusionCounts(hit: 0, miss: 0, falsePositive: 0, ambiguous: 0, insufficient: 1)
            : confusionCounts(expected: matrixCase.expectedMIDINotes, detected: detected)
        if matrixCase.insufficient {
            try requireMatrix(detected.isEmpty, caseID: matrixCase.id, detail: "insufficient trace became a note claim")
        }
        try assertMatrix(actual, equals: matrixCase.expected, caseID: matrixCase.id)
    }
}

private struct ReplayConfusionMatrixDocument: Decodable {
    let confusionMatrix: ReplayConfusionMatrix
}

private struct ReplayConfusionMatrix: Decodable {
    let schemaVersion: Int
    let cases: [ReplayConfusionMatrixCase]
}

private struct ReplayConfusionMatrixCase: Decodable {
    enum Source: String, Decodable {
        case midi
        case targetAudio
    }

    let id: String
    let source: Source
    let capability: MatrixCapability
    let calibrationVersion: String
    let observationIDs: [String]
    let expectedMIDINotes: [Int]
    let expected: ConfusionCounts
    let rationale: String
}

private struct HandConfusionMatrixDocument: Decodable {
    let confusionMatrix: HandConfusionMatrix
}

private struct HandConfusionMatrix: Decodable {
    let schemaVersion: Int
    let cases: [HandConfusionMatrixCase]
}

private struct HandConfusionMatrixCase: Decodable {
    let id: String
    let capability: MatrixCapability
    let calibrationVersion: Int
    let traceIDs: [String]
    let expectedMIDINotes: [Int]
    let insufficient: Bool
    let expected: ConfusionCounts
    let rationale: String
}

private enum MatrixCapability: String, Decodable {
    case observed
    case degraded

    func matches(_ evidence: PerformanceInputCapabilities.Evidence) -> Bool {
        switch (self, evidence) {
        case (.observed, .observed), (.degraded, .degraded):
            true
        case (.observed, .degraded), (.observed, .unavailable), (.degraded, .observed), (.degraded, .unavailable):
            false
        }
    }
}

private struct ConfusionCounts: Decodable, Equatable {
    let hit: Int
    let miss: Int
    let falsePositive: Int
    let ambiguous: Int
    let insufficient: Int
}

private enum PerformanceObservationMatrixError: Error, LocalizedError {
    case violation(caseID: String, detail: String)
    case mismatch(caseID: String, expected: ConfusionCounts, actual: ConfusionCounts)

    var errorDescription: String? {
        switch self {
        case let .violation(caseID, detail):
            "requirement=P15-OBSERVATION-MATRIX-\(caseID) violation=\(detail)"
        case let .mismatch(caseID, expected, actual):
            "requirement=P15-OBSERVATION-MATRIX-\(caseID) expected=\(expected) actual=\(actual)"
        }
    }
}

private func confusionCounts(
    expected: [Int],
    detected: [Int],
    ambiguous: Int = 0,
    insufficient: Int = 0
) -> ConfusionCounts {
    let expectedNotes = Set(expected)
    let detectedNotes = Set(detected)
    return ConfusionCounts(
        hit: expectedNotes.intersection(detectedNotes).count,
        miss: expectedNotes.subtracting(detectedNotes).count,
        falsePositive: detectedNotes.subtracting(expectedNotes).count,
        ambiguous: ambiguous,
        insufficient: insufficient
    )
}

private func assertMatrix(
    _ actual: ConfusionCounts,
    equals expected: ConfusionCounts,
    caseID: String
) throws {
    guard actual == expected else {
        throw PerformanceObservationMatrixError.mismatch(caseID: caseID, expected: expected, actual: actual)
    }
}

private func requireMatrix(
    _ condition: @autoclosure () -> Bool,
    caseID: String,
    detail: String
) throws {
    guard condition() else {
        throw PerformanceObservationMatrixError.violation(caseID: caseID, detail: detail)
    }
}
