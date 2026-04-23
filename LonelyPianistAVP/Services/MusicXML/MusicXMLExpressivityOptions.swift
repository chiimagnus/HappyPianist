import Foundation

struct MusicXMLExpressivityOptions: Equatable {
    var wedgeEnabled: Bool = false
    var graceEnabled: Bool = false
    var fermataEnabled: Bool = false
    var arpeggiateEnabled: Bool = false
    var wordsSemanticsEnabled: Bool = false

    init(
        wedgeEnabled: Bool = false,
        graceEnabled: Bool = false,
        fermataEnabled: Bool = false,
        arpeggiateEnabled: Bool = false,
        wordsSemanticsEnabled: Bool = false
    ) {
        self.wedgeEnabled = wedgeEnabled
        self.graceEnabled = graceEnabled
        self.fermataEnabled = fermataEnabled
        self.arpeggiateEnabled = arpeggiateEnabled
        self.wordsSemanticsEnabled = wordsSemanticsEnabled
    }
}
