import Foundation

public struct PracticeHistoricalPreferences: Equatable, Sendable {
    public let handMode: PracticeHandMode
    public let tempoScale: Double
    public let loopEnabled: Bool
    public let requiredSuccesses: Int

    public init(
        handMode: PracticeHandMode,
        tempoScale: Double,
        loopEnabled: Bool,
        requiredSuccesses: Int
    ) {
        self.handMode = handMode
        self.tempoScale = min(
            max(tempoScale, PracticeRoundConfiguration.supportedTempoRange.lowerBound),
            PracticeRoundConfiguration.supportedTempoRange.upperBound
        )
        self.loopEnabled = loopEnabled
        self.requiredSuccesses = min(
            max(requiredSuccesses, PracticeRoundConfiguration.supportedSuccessRange.lowerBound),
            PracticeRoundConfiguration.supportedSuccessRange.upperBound
        )
    }
}

public enum PracticeLaunchRestorePolicy: Equatable, Sendable {
    case exactAvailable
    case historicalPreferences(PracticeHistoricalPreferences)
    case freshDefaults
}
