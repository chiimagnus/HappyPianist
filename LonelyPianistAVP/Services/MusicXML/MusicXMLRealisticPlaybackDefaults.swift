import Foundation

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
