public struct MusicXMLExpressivityOptions: Equatable, Sendable {
    public var wedgeEnabled: Bool = false
    public var graceEnabled: Bool = false
    public var fermataEnabled: Bool = false
    public var arpeggiateEnabled: Bool = false
    public var wordsSemanticsEnabled: Bool = false
}

public enum MusicXMLRealisticPlaybackDefaults {
    public static let practiceScoreOrder: MusicXMLScoreOrder = .written
    public static let referencePlaybackScoreOrder: MusicXMLScoreOrder = .performed
    public static let performanceTimingEnabled = true

    public static let expressivityOptions = MusicXMLExpressivityOptions(
        wedgeEnabled: true,
        graceEnabled: true,
        fermataEnabled: true,
        arpeggiateEnabled: true,
        wordsSemanticsEnabled: true
    )
}
