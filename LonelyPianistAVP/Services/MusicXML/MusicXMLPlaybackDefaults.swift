struct MusicXMLExpressivityOptions: Equatable {
    var wedgeEnabled: Bool = false
    var graceEnabled: Bool = false
    var fermataEnabled: Bool = false
    var arpeggiateEnabled: Bool = false
    var wordsSemanticsEnabled: Bool = false
}

enum MusicXMLRealisticPlaybackDefaults {
    static let shouldExpandStructure = false
    static let performanceTimingEnabled = true
    static let audioRecognitionEnabled = true

    static let expressivityOptions = MusicXMLExpressivityOptions(
        wedgeEnabled: true,
        graceEnabled: true,
        fermataEnabled: true,
        arpeggiateEnabled: true,
        wordsSemanticsEnabled: true
    )
}
