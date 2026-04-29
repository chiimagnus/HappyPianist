@testable import LonelyPianistAVP
import Testing

@Test
func musicXMLRealisticPlaybackDefaultsAreHardcodedForNoSettingsSwitches() {
    let expressivity = MusicXMLRealisticPlaybackDefaults.expressivityOptions

    #expect(MusicXMLRealisticPlaybackDefaults.shouldExpandStructure == false)
    #expect(MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled == true)
    #expect(MusicXMLRealisticPlaybackDefaults.audioRecognitionEnabled == true)
    #expect(expressivity.wedgeEnabled == true)
    #expect(expressivity.graceEnabled == true)
    #expect(expressivity.fermataEnabled == true)
    #expect(expressivity.arpeggiateEnabled == true)
    #expect(expressivity.wordsSemanticsEnabled == true)
}

// Grep gate for local/CI regression checks:
// rg -n 'UserDefaults\.standard\.bool\(forKey:
// "practiceMusicXML|@AppStorage\("practiceMusicXML|practiceAudioRecognitionEnabled\b' LonelyPianistAVP || true
