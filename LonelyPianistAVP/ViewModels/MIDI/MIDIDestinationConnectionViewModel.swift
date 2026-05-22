import Foundation
import Observation

@MainActor
@Observable
final class MIDIDestinationConnectionViewModel {
    private let outputService: CoreMIDIOutputService

    var destinations: [MIDIDestinationInfo] = []
    var lastErrorMessage: String?

    init(outputService: CoreMIDIOutputService? = nil) {
        let outputService = outputService ?? CoreMIDIOutputService()
        self.outputService = outputService

        outputService.onDestinationListChange = { [weak self] destinations in
            Task { @MainActor [weak self] in
                self?.destinations = destinations
            }
        }

        outputService.onLastErrorMessageChange = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.lastErrorMessage = message
            }
        }
    }

    func start() {
        do {
            try outputService.start()
            destinations = outputService.listDestinations()
        } catch {
            lastErrorMessage = error.localizedDescription
            destinations = []
        }
    }

    func stop() {
        outputService.stop()
    }

    func refreshDestinations() {
        destinations = outputService.listDestinations()
    }

    func sendLocalControlOff(_ enabled: Bool, destinationUniqueID: Int32) {
        let value: UInt8 = enabled ? 0 : 127
        do {
            for channel in UInt8(0) ..< 16 {
                try outputService.sendControlChange(
                    controller: 122,
                    value: value,
                    channel: channel,
                    destinationUniqueID: destinationUniqueID
                )
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
