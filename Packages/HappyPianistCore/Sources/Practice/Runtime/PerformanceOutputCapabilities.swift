import Foundation
import MusicXML

public enum PerformanceControllerValueSupport: Equatable, Sendable {
    case binary
    case continuous
}

public struct PerformanceOutputApproximation: Equatable, Sendable {
    public let controllerNumber: UInt8
    public let sourceValue: UInt8
    public let renderedValue: UInt8

    public init(controllerNumber: UInt8, sourceValue: UInt8, renderedValue: UInt8) {
        self.controllerNumber = controllerNumber
        self.sourceValue = sourceValue
        self.renderedValue = renderedValue
    }
}

public struct PerformanceControllerValueResolution: Equatable, Sendable {
    public let value: UInt8
    public let approximation: PerformanceOutputApproximation?

    public init(value: UInt8, approximation: PerformanceOutputApproximation?) {
        self.value = value
        self.approximation = approximation
    }
}

public struct PerformanceOutputCapabilities: Equatable, Sendable {
    public static let localSampler = PerformanceOutputCapabilities(
        damper: .binary,
        sostenuto: .binary,
        soft: .binary
    )
    public static let externalMIDI = PerformanceOutputCapabilities(
        damper: .continuous,
        sostenuto: .continuous,
        soft: .continuous
    )

    public let damper: PerformanceControllerValueSupport
    public let sostenuto: PerformanceControllerValueSupport
    public let soft: PerformanceControllerValueSupport

    public init(
        damper: PerformanceControllerValueSupport,
        sostenuto: PerformanceControllerValueSupport,
        soft: PerformanceControllerValueSupport
    ) {
        self.damper = damper
        self.sostenuto = sostenuto
        self.soft = soft
    }

    public func resolve(controllerNumber: UInt8, value: UInt8) -> PerformanceControllerValueResolution {
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
