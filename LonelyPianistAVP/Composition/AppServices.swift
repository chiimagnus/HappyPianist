import Foundation
import Observation

@MainActor
@Observable
final class AppServices {
    let worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol
    let keyGeometryService: PianoKeyGeometryServiceProtocol
    let importService: MusicXMLImportServiceProtocol
    let parser: MusicXMLParserProtocol
    let stepBuilder: PracticeStepBuilderProtocol
    let arTrackingService: ARTrackingServiceProtocol
    let calibrationCaptureService: CalibrationPointCaptureService
    let practicePreparationService: PracticePreparationServiceProtocol
    let songLibraryIndexStore: SongLibraryIndexStoreProtocol
    let songFileStore: SongFileStoreProtocol
    let audioImportService: AudioImportServiceProtocol
    let songLibraryPaths: SongLibraryPaths
    let bundledSongLibraryProvider: BundledSongLibraryProviderProtocol
    let songAudioPlayer: SongAudioPlayerProtocol
    let calibrationRepository: CalibrationRepositoryProtocol
    let pianoModeRegistry: PianoModeRegistryProtocol
    let practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol

    init(
        worldAnchorCalibrationStore: WorldAnchorCalibrationStoreProtocol? = nil,
        keyGeometryService: PianoKeyGeometryServiceProtocol? = nil,
        importService: MusicXMLImportServiceProtocol? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil,
        arTrackingService: ARTrackingServiceProtocol? = nil,
        calibrationCaptureService: CalibrationPointCaptureService? = nil,
        practicePreparationService: PracticePreparationServiceProtocol? = nil,
        calibrationRepository: CalibrationRepositoryProtocol? = nil,
        pianoModeRegistry: PianoModeRegistryProtocol? = nil,
        practiceSessionViewModelFactory: PracticeSessionViewModelFactoryProtocol? = nil
    ) {
        self.worldAnchorCalibrationStore = worldAnchorCalibrationStore ?? WorldAnchorCalibrationStore()
        self.keyGeometryService = keyGeometryService ?? PianoKeyGeometryService()
        self.importService = importService ?? MusicXMLImportService()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        self.arTrackingService = arTrackingService ?? ARTrackingService()
        self.calibrationCaptureService = calibrationCaptureService ?? CalibrationPointCaptureService()
        songLibraryIndexStore = SongLibraryIndexStore()
        songFileStore = SongFileStore()
        audioImportService = AudioImportService()
        songLibraryPaths = SongLibraryPaths()
        bundledSongLibraryProvider = BundledSongLibraryProvider()
        songAudioPlayer = SongAudioPlayer()
        self.practicePreparationService = practicePreparationService
            ?? PracticePreparationService(parser: self.parser, stepBuilder: self.stepBuilder)
        self.calibrationRepository = calibrationRepository
            ?? CalibrationRepository(worldAnchorCalibrationStore: self.worldAnchorCalibrationStore)

        let makePressDetectionService: () -> PressDetectionServiceProtocol = {
            PressDetectionService()
        }
        let makeChordAttemptAccumulator: () -> ChordAttemptAccumulatorProtocol = {
            ChordAttemptAccumulator()
        }
        let makeSleeper: () -> SleeperProtocol = {
            TaskSleeper()
        }
        let makeSequencerPlaybackService: () -> PracticeSequencerPlaybackServiceProtocol = {
            AVAudioSequencerPracticePlaybackService(soundFontResourceName: "SalC5Light2")
        }
        let makeAudioStepAttemptAccumulator: () -> AudioStepAttemptAccumulator = {
            AudioStepAttemptAccumulator()
        }
        let makeHandPianoActivityGate: () -> HandPianoActivityGate = {
            HandPianoActivityGate()
        }
        let makeAudioRecognitionService: () -> PracticeAudioRecognitionServiceProtocol? = {
            #if targetEnvironment(simulator)
                nil
            #else
                PracticeAudioRecognitionService()
            #endif
        }
        let makeBluetoothMIDIEventSource: () -> PracticeInputEventSourceProtocol = {
            BluetoothMIDIInputEventSourceService()
        }

        let resolvedPianoModeRegistry: PianoModeRegistryProtocol = pianoModeRegistry ??
            PianoModeRegistryService(modes: [
                RealAudioPianoMode(makePracticeSessionViewModel: {
                    PracticeSessionViewModel(
                        pressDetectionService: makePressDetectionService(),
                        chordAttemptAccumulator: makeChordAttemptAccumulator(),
                        sleeper: makeSleeper(),
                        sequencerPlaybackService: makeSequencerPlaybackService(),
                        audioRecognitionService: makeAudioRecognitionService(),
                        practiceInputEventSource: nil,
                        audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                        handPianoActivityGate: makeHandPianoActivityGate()
                    )
                }),
                BluetoothMIDIPianoMode(makePracticeSessionViewModel: {
                    PracticeSessionViewModel(
                        pressDetectionService: makePressDetectionService(),
                        chordAttemptAccumulator: makeChordAttemptAccumulator(),
                        sleeper: makeSleeper(),
                        sequencerPlaybackService: makeSequencerPlaybackService(),
                        audioRecognitionService: nil,
                        practiceInputEventSource: makeBluetoothMIDIEventSource(),
                        audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                        handPianoActivityGate: makeHandPianoActivityGate()
                    )
                }),
                VirtualPianoMode(makePracticeSessionViewModel: {
                    PracticeSessionViewModel(
                        pressDetectionService: makePressDetectionService(),
                        chordAttemptAccumulator: makeChordAttemptAccumulator(),
                        sleeper: makeSleeper(),
                        sequencerPlaybackService: makeSequencerPlaybackService(),
                        audioRecognitionService: nil,
                        practiceInputEventSource: nil,
                        audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                        handPianoActivityGate: makeHandPianoActivityGate()
                    )
                }),
            ])
        self.pianoModeRegistry = resolvedPianoModeRegistry

        self.practiceSessionViewModelFactory = practiceSessionViewModelFactory
            ?? PracticeSessionViewModelFactoryService(
                pianoModeRegistry: resolvedPianoModeRegistry,
                makeFallbackPracticeSessionViewModel: {
                    PracticeSessionViewModel(
                        pressDetectionService: makePressDetectionService(),
                        chordAttemptAccumulator: makeChordAttemptAccumulator(),
                        sleeper: makeSleeper(),
                        sequencerPlaybackService: makeSequencerPlaybackService(),
                        audioRecognitionService: makeAudioRecognitionService(),
                        practiceInputEventSource: nil,
                        audioStepAttemptAccumulator: makeAudioStepAttemptAccumulator(),
                        handPianoActivityGate: makeHandPianoActivityGate()
                    )
                }
            )
    }
}
