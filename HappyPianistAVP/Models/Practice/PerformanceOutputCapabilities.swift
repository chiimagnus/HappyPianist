import Foundation

enum PerformanceControllerValueSupport: Equatable, Sendable {
    case binary
    case continuous
}

struct PerformanceOutputApproximation: Equatable, Sendable {
    let controllerNumber: UInt8
    let sourceValue: UInt8
    let renderedValue: UInt8
}

struct PerformanceControllerValueResolution: Equatable, Sendable {
    let value: UInt8
    let approximation: PerformanceOutputApproximation?
}

struct PerformanceOutputCapabilities: Equatable, Sendable {
    static let localSampler = PerformanceOutputCapabilities(
        damper: .binary,
        sostenuto: .binary,
        soft: .binary
    )
    static let externalMIDI = PerformanceOutputCapabilities(
        damper: .continuous,
        sostenuto: .continuous,
        soft: .continuous
    )

    let damper: PerformanceControllerValueSupport
    let sostenuto: PerformanceControllerValueSupport
    let soft: PerformanceControllerValueSupport

    func resolve(controllerNumber: UInt8, value: UInt8) -> PerformanceControllerValueResolution {
        guard support(for: controllerNumber) == .binary else {
            return PerformanceControllerValueResolution(value: value, approximation: nil)
        }
        let renderedValue: UInt8 = value >= 64 ? 127 : 0
        return PerformanceControllerValueResolution(
            value: renderedValue,
            approximation: renderedValue == value ? nil : PerformanceOutputApproximation(
                controllerNumber: controllerNumber,
                sourceValue: value,
                renderedValue: renderedValue
            )
        )
    }

    private func support(for controllerNumber: UInt8) -> PerformanceControllerValueSupport {
        switch controllerNumber {
        case MusicXMLPedalController.damper.rawValue:
            damper
        case MusicXMLPedalController.sostenuto.rawValue:
            sostenuto
        case MusicXMLPedalController.soft.rawValue:
            soft
        default:
            .continuous
        }
    }
}
