import Foundation

struct PianoTouchVelocityResolver {
    let calibration: PianoTouchCalibration

    func resolve(normalVelocityMetersPerSecond: Float?) -> UInt8? {
        guard
            let normalVelocityMetersPerSecond,
            normalVelocityMetersPerSecond.isFinite
        else { return nil }

        let strikeSpeed = -normalVelocityMetersPerSecond
        guard strikeSpeed >= calibration.minimumStrikeSpeedMetersPerSecond else { return nil }

        let speedRange = calibration.fullScaleStrikeSpeedMetersPerSecond
            - calibration.minimumStrikeSpeedMetersPerSecond
        let normalizedSpeed = min(
            1,
            (strikeSpeed - calibration.minimumStrikeSpeedMetersPerSecond) / speedRange
        )
        let shapedSpeed = pow(normalizedSpeed, calibration.curveExponent)
        let velocityRange = Float(calibration.maximumVelocity - calibration.minimumVelocity)
        return calibration.minimumVelocity + UInt8((shapedSpeed * velocityRange).rounded())
    }
}
