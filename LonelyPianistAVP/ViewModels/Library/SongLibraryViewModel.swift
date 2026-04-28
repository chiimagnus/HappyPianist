import Foundation
import Observation

@MainActor
@Observable
final class SongLibraryViewModel {
    private let appModel: AppModel
    private let indexStore: SongLibraryIndexStoreProtocol
    private let fileStore: SongFileStoreProtocol
    private let audioImportService: AudioImportServiceProtocol
    private let paths: SongLibraryPaths
    private let bundledProvider: BundledSongLibraryProviderProtocol
    private let bundledEntries: [SongLibraryEntry]
    private let parser: MusicXMLParserProtocol
    private let stepBuilder: PracticeStepBuilderProtocol
    private let audioPlaybackController: SongAudioPlaybackStateController
    private let structureExpander = MusicXMLStructureExpander()

    var index: SongLibraryIndex = .empty
    var errorMessage: String?
    var currentListeningEntryID: UUID?
    var isCurrentListeningPlaying = false
    var isMusicXMLImporterPresented = false

    init(
        appModel: AppModel,
        indexStore: SongLibraryIndexStoreProtocol? = nil,
        fileStore: SongFileStoreProtocol? = nil,
        audioImportService: AudioImportServiceProtocol? = nil,
        paths: SongLibraryPaths? = nil,
        bundledProvider: BundledSongLibraryProviderProtocol? = nil,
        parser: MusicXMLParserProtocol? = nil,
        stepBuilder: PracticeStepBuilderProtocol? = nil,
        audioPlayer: SongAudioPlayerProtocol? = nil
    ) {
        self.appModel = appModel
        self.indexStore = indexStore ?? SongLibraryIndexStore()
        self.fileStore = fileStore ?? SongFileStore()
        self.audioImportService = audioImportService ?? AudioImportService()
        self.paths = paths ?? SongLibraryPaths()
        let resolvedBundledProvider = bundledProvider ?? BundledSongLibraryProvider()
        self.bundledProvider = resolvedBundledProvider
        bundledEntries = resolvedBundledProvider.bundledEntries()
        self.parser = parser ?? MusicXMLParser()
        self.stepBuilder = stepBuilder ?? PracticeStepBuilder()
        audioPlaybackController = SongAudioPlaybackStateController(player: audioPlayer ?? SongAudioPlayer())

        audioPlaybackController.onStateChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncListeningState()
            }
        }

        reload()
    }

    var entries: [SongLibraryEntry] {
        var merged: [SongLibraryEntry] = []
        merged.reserveCapacity(bundledEntries.count + index.entries.count)

        let bundledNames = Set(bundledEntries.map(\.displayName))
        merged.append(contentsOf: bundledEntries)

        for entry in index.entries where bundledNames.contains(entry.displayName) == false {
            merged.append(entry)
        }

        return merged
    }

    func reload() {
        do {
            index = try indexStore.load()
        } catch {
            errorMessage = "加载乐曲库失败：\(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func didTapImportMusicXML() {
        isMusicXMLImporterPresented = true
    }

    func importMusicXML(from selectedURLs: [URL]) {
        guard selectedURLs.isEmpty == false else { return }

        do {
            var updatedIndex = try indexStore.load()

            for url in selectedURLs {
                let imported = try fileStore.importMusicXML(from: url)
                let entry = SongLibraryEntry(
                    id: UUID(),
                    displayName: URL(fileURLWithPath: imported.sourceFileName)
                        .deletingPathExtension()
                        .lastPathComponent,
                    musicXMLFileName: imported.storedFileName,
                    importedAt: imported.importedAt,
                    audioFileName: nil
                )

                var nextIndex = updatedIndex
                nextIndex.entries.append(entry)

                do {
                    try indexStore.save(nextIndex)
                    updatedIndex = nextIndex
                } catch {
                    try? fileStore.deleteScoreFile(named: imported.storedFileName)
                    throw error
                }
            }
            index = updatedIndex
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    func preparePractice(entryID: UUID) -> Bool {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return false
        }

        do {
            let scoreURL: URL
            if entry.isBundled == true {
                guard let bundledURL = bundledProvider.musicXMLURL(fileName: entry.musicXMLFileName) else {
                    errorMessage = "未在应用资源中找到该曲谱文件。"
                    return false
                }
                scoreURL = bundledURL
            } else {
                scoreURL = try paths.scoresDirectoryURL().appendingPathComponent(entry.musicXMLFileName)
            }
            let score = try parser.parse(fileURL: scoreURL)
            let shouldExpandStructure = MusicXMLRealisticPlaybackDefaults.shouldExpandStructure
            let primaryPartIDForExpansion = score.preferredPrimaryPartID()
            let effectiveScore = shouldExpandStructure
                ? structureExpander.expandStructureIfPossible(score: score, primaryPartID: primaryPartIDForExpansion)
                : score
            let primaryPartID = effectiveScore.preferredPrimaryPartID(preferredPartID: primaryPartIDForExpansion)
            let practiceScore = effectiveScore.filtering(toPartID: primaryPartID)

            let expressivityOptions = MusicXMLRealisticPlaybackDefaults.expressivityOptions
            let buildResult = stepBuilder.buildSteps(from: practiceScore, expressivity: expressivityOptions)
            let wordsSemantics = expressivityOptions.wordsSemanticsEnabled
                ? MusicXMLWordsSemanticsInterpreter().interpret(
                    wordsEvents: practiceScore.wordsEvents,
                    tempoEvents: practiceScore.tempoEvents
                )
                : nil
            let tempoMap = MusicXMLTempoMap(
                tempoEvents: practiceScore.tempoEvents + (wordsSemantics?.derivedTempoEvents ?? []),
                tempoRamps: wordsSemantics?.derivedTempoRamps ?? [],
                partID: primaryPartID
            )
            let pedalTimeline = MusicXMLPedalTimeline(events: practiceScore
                .pedalEvents + (wordsSemantics?.derivedPedalEvents ?? []))
            let fermataTimeline = expressivityOptions.fermataEnabled
                ? MusicXMLFermataTimeline(fermataEvents: practiceScore.fermataEvents, notes: practiceScore.notes)
                : nil
            let attributeTimeline = MusicXMLAttributeTimeline(
                timeSignatureEvents: practiceScore.timeSignatureEvents,
                keySignatureEvents: practiceScore.keySignatureEvents,
                clefEvents: practiceScore.clefEvents
            )
            let slurTimeline = MusicXMLSlurTimeline(events: practiceScore.slurEvents)
            let shouldUsePerformanceTiming = MusicXMLRealisticPlaybackDefaults.performanceTimingEnabled
            let noteSpans = MusicXMLNoteSpanBuilder().buildSpans(
                from: practiceScore.notes,
                performanceTimingEnabled: shouldUsePerformanceTiming,
                expressivity: expressivityOptions,
                fermataTimeline: fermataTimeline
            )
            let highlightGuides = PianoHighlightGuideBuilderService().buildGuides(
                input: PianoHighlightGuideBuildInput(
                    score: practiceScore,
                    steps: buildResult.steps,
                    noteSpans: noteSpans,
                    expressivity: expressivityOptions
                )
            )

            guard buildResult.steps.isEmpty == false else {
                errorMessage = "该曲目未生成可练习步骤。"
                return false
            }

            appModel.setImportedSteps(
                buildResult.steps,
                file: ImportedMusicXMLFile(
                    fileName: entry.displayName,
                    storedURL: scoreURL,
                    importedAt: entry.importedAt
                ),
                tempoMap: tempoMap,
                pedalTimeline: pedalTimeline,
                fermataTimeline: fermataTimeline,
                attributeTimeline: attributeTimeline,
                slurTimeline: slurTimeline,
                noteSpans: noteSpans,
                highlightGuides: highlightGuides
            )

            var updatedIndex = index
            updatedIndex.lastSelectedEntryID = entry.id
            try? indexStore.save(updatedIndex)
            index = updatedIndex

            return true
        } catch {
            errorMessage = "加载曲目失败：\(error.localizedDescription)"
            return false
        }
    }

    func deleteEntry(entryID: UUID) {
        if bundledEntries.contains(where: { $0.id == entryID }) {
            errorMessage = "内置曲目无法删除。"
            return
        }
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        let entry = index.entries[entryIndex]
        if currentListeningEntryID == entry.id {
            stopListening()
        }

        do {
            var updatedIndex = index
            updatedIndex.entries.remove(at: entryIndex)

            if updatedIndex.lastSelectedEntryID == entry.id {
                updatedIndex.lastSelectedEntryID = updatedIndex.entries.last?.id
            }

            try indexStore.save(updatedIndex)
            index = updatedIndex

            do {
                try fileStore.deleteScoreFile(named: entry.musicXMLFileName)
                if let audioFileName = entry.audioFileName {
                    try fileStore.deleteAudioFile(named: audioFileName)
                }
            } catch {
                errorMessage = "曲目已从索引移除，但文件删除失败：\(error.localizedDescription)"
            }
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    func bindAudio(entryID: UUID, from sourceURL: URL) {
        if bundledEntries.contains(where: { $0.id == entryID }) {
            errorMessage = "内置曲目不支持绑定外部音频文件。"
            return
        }
        guard let entryIndex = index.entries.firstIndex(where: { $0.id == entryID }) else {
            return
        }

        do {
            let importedAudioFileName = try audioImportService.importAudio(from: sourceURL)

            var updatedIndex = index
            let previousAudioFileName = updatedIndex.entries[entryIndex].audioFileName
            updatedIndex.entries[entryIndex].audioFileName = importedAudioFileName

            do {
                try indexStore.save(updatedIndex)
                index = updatedIndex
                if let previousAudioFileName {
                    try? fileStore.deleteAudioFile(named: previousAudioFileName)
                }
            } catch {
                try? fileStore.deleteAudioFile(named: importedAudioFileName)
                throw error
            }
        } catch {
            errorMessage = "导入音频失败：\(error.localizedDescription)"
        }
    }

    func didTapListen(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else {
            return
        }
        guard let audioFileName = entry.audioFileName else {
            errorMessage = "此曲目未绑定音频文件，可再次导入音频。"
            return
        }

        do {
            let audioURL: URL
            if entry.isBundled == true {
                guard let bundledURL = bundledProvider.audioURL(fileName: audioFileName) else {
                    errorMessage = "未在应用资源中找到该音频文件。"
                    return
                }
                audioURL = bundledURL
            } else {
                audioURL = try fileStore.audioFileURL(fileName: audioFileName)
            }
            try audioPlaybackController.toggle(entryID: entryID, url: audioURL)
            syncListeningState()
        } catch {
            errorMessage = "播放失败：\(error.localizedDescription)"
        }
    }

    func stopListening() {
        audioPlaybackController.stop()
        syncListeningState()
    }

    func isListeningPlaying(entryID: UUID) -> Bool {
        currentListeningEntryID == entryID && isCurrentListeningPlaying
    }

    private func syncListeningState() {
        currentListeningEntryID = audioPlaybackController.currentEntryID
        if let currentListeningEntryID {
            isCurrentListeningPlaying = audioPlaybackController.isPlaying(entryID: currentListeningEntryID)
        } else {
            isCurrentListeningPlaying = false
        }
    }
}
