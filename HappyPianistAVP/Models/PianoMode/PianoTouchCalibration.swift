import Foundation

struct PianoTouchCalibration: Codable, Equatable {
    static let currentVersion = 1

    let id: UUID
    let version: Int
    let planeOffsetMeters: Float
    let releaseHysteresisMeters: Float
    let minimumStrikeSpeedMetersPerSecond: Float
    let fullScaleStrikeSpeedMetersPerSecond: Float
    let minimumVelocity: UInt8
    let maximumVelocity: UInt8
    let curveExponent: Float
    let retriggerDebounceSeconds: TimeInterval

    var releaseThresholdMeters: Float {
        planeOffsetMeters + releaseHysteresisMeters
    }

    init(
        id: UUID = UUID(),
        planeOffsetMeters: Float,
        releaseHysteresisMeters: Float,
        minimumStrikeSpeedMetersPerSecond: Float,
        fullScaleStrikeSpeedMetersPerSecond: Float,
        minimumVelocity: UInt8,
        maximumVelocity: UInt8,
        curveExponent: Float,
        retriggerDebounceSeconds: TimeInterval
    ) {
        self.id = id
        version = Self.currentVersion
        self.planeOffsetMeters = max(0, planeOffsetMeters)
        self.releaseHysteresisMeters = max(0, releaseHysteresisMeters)
        self.minimumStrikeSpeedMetersPerSecond = max(0, minimumStrikeSpeedMetersPerSecond)
        self.fullScaleStrikeSpeedMetersPerSecond = max(
            self.minimumStrikeSpeedMetersPerSecond + 0.01,
            fullScaleStrikeSpeedMetersPerSecond
        )
        self.minimumVelocity = min(127, minimumVelocity)
        self.maximumVelocity = max(self.minimumVelocity, min(127, maximumVelocity))
        self.curveExponent = max(0.1, curveExponent)
        self.retriggerDebounceSeconds = max(0, retriggerDebounceSeconds)
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(UUID.self, forKey: .id)
        let version = try values.decode(Int.self, forKey: .version)
        let planeOffset = try values.decode(Float.self, forKey: .planeOffsetMeters)
        let hysteresis = try values.decode(Float.self, forKey: .releaseHysteresisMeters)
        let minimumStrikeSpeed = try values.decode(Float.self, forKey: .minimumStrikeSpeedMetersPerSecond)
        let fullScaleStrikeSpeed = try values.decode(Float.self, forKey: .fullScaleStrikeSpeedMetersPerSecond)
        let minimumVelocity = try values.decode(UInt8.self, forKey: .minimumVelocity)
        let maximumVelocity = try values.decode(UInt8.self, forKey: .maximumVelocity)
        let curveExponent = try values.decode(Float.self, forKey: .curveExponent)
        let retriggerDebounce = try values.decode(TimeInterval.self, forKey: .retriggerDebounceSeconds)

        guard
            version == Self.currentVersion,
            planeOffset.isFinite, planeOffset >= 0,
            hysteresis.isFinite, hysteresis >= 0,
            minimumStrikeSpeed.isFinite, minimumStrikeSpeed >= 0,
            fullScaleStrikeSpeed.isFinite, fullScaleStrikeSpeed > minimumStrikeSpeed,
            minimumVelocity <= maximumVelocity, maximumVelocity <= 127,
            curveExponent.isFinite, curveExponent >= 0.1,
            retriggerDebounce.isFinite, retriggerDebounce >= 0
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid piano touch calibration")
            )
        }

        self.id = id
        self.version = version
        planeOffsetMeters = planeOffset
        releaseHysteresisMeters = hysteresis
        minimumStrikeSpeedMetersPerSecond = minimumStrikeSpeed
        fullScaleStrikeSpeedMetersPerSecond = fullScaleStrikeSpeed
        self.minimumVelocity = minimumVelocity
        self.maximumVelocity = maximumVelocity
        self.curveExponent = curveExponent
        retriggerDebounceSeconds = retriggerDebounce
    }
}
