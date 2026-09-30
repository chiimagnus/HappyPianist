import Diagnostics
import Foundation
import Library
import MusicXML
import Notation
import Observation
import Practice

@MainActor
@Observable
final class LibraryScorePreviewViewModel {
    enum State {
        case idle
        case loading
        case ready
        case failure(PracticeLaunchFailure)
    }

    private let resolver: any SongLibraryEntryResolving
    private let preparationService: any PracticePreparationServiceProtocol
    private let diagnosticsReporter: any DiagnosticsReporting
    let pageOwner = GrandStaffNotationPageViewModel()
    private(set) var state: State = .idle
    private(set) var identity: SongPracticeLibrarySelectionIdentity?
    private(set) var prepared: PreparedPractice?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(resolver: any SongLibraryEntryResolving, preparationService: any PracticePreparationServiceProtocol, diagnosticsReporter: any DiagnosticsReporting) {
        self.resolver = resolver
        self.preparationService = preparationService
        self.diagnosticsReporter = diagnosticsReporter
    }

    var isOpen: Bool { identity != nil }

    static func annotations(overview: SongPracticeLibraryOverview, plan: GrandStaffNotationPagePlan, selection: SongPracticeLibrarySelectionIdentity) -> [GrandStaffNotationMeasureAnnotation] {
        guard overview.identity == selection, overview.identity.songID == plan.input.identity.songID,
              overview.scoreRevision == plan.input.identity.scoreRevision,
              case .available = overview.measureProgress else { return [] }
        let focusIDs = Set(overview.focusMeasures.map(\.sourceMeasureID))
        return plan.input.measureSpans.map { span in
            let state: GrandStaffNotationMeasureAnnotation.State = switch overview.sourceMeasureStates[span.sourceMeasureID] {
            case .stable: .stable
            case .learning: .learning
            case nil: .unpracticed
            }
            return GrandStaffNotationMeasureAnnotation(occurrenceID: span.occurrenceID, state: state, isResume: overview.resumeSourceMeasureID == span.sourceMeasureID, isFocus: focusIDs.contains(span.sourceMeasureID))
        }
    }

    func open(_ identity: SongPracticeLibrarySelectionIdentity, isCurrent: @escaping @MainActor () -> Bool) {
        close()
        guard isCurrent() else { return }
        self.identity = identity
        state = .loading
        let requestGeneration = generation
        task = Task { [weak self] in
            guard let self else { return }
            var fileReference: DiagnosticFileReference?
            do {
                let resolved = try await resolver.resolve(songID: identity.songID).get()
                guard accepts(requestGeneration, isCurrent: isCurrent) else { return }
                guard resolved.entry.id == identity.songID,
                      resolved.entry.scoreFileVersionID == identity.scoreFileVersionID else {
                    close()
                    return
                }
                fileReference = resolved.diagnosticFileReference
                let prepared = try await preparationService.prepare(
                    songID: identity.songID,
                    from: resolved.scoreURL,
                    file: ImportedMusicXMLFile(fileName: resolved.entry.displayName, storedURL: resolved.scoreURL, importedAt: resolved.entry.importedAt),
                    options: .practice
                )
                guard accepts(requestGeneration, isCurrent: isCurrent) else { return }
                guard prepared.identity.songID == identity.songID, !prepared.steps.isEmpty else {
                    throw PracticePreparationError.noPlayableNotes
                }
                guard !prepared.measureSpans.isEmpty else { throw PracticePreparationError.missingMeasureStructure }
                self.prepared = prepared
                await pageOwner.load(GrandStaffNotationScoreInput(
                    identity: prepared.identity,
                    projection: prepared.notationProjection,
                    measureSpans: prepared.measureSpans,
                    facts: PracticeNotationScoreFacts(logicalInstrument: prepared.scoreContext.logicalInstrument, structuralPartID: prepared.scoreContext.structuralPartID),
                    attributeTimeline: prepared.attributeTimeline
                ))
                guard accepts(requestGeneration, isCurrent: isCurrent) else { return }
                guard pageOwner.plan != nil else {
                    throw PracticePreparationError.unexpected(stage: "libraryScorePagination", reason: pageOwner.failureMessage ?? "No page plan")
                }
                state = .ready
                task = nil
            } catch {
                guard accepts(requestGeneration, isCurrent: isCurrent) else { return }
                let resolutionError = error as? SongLibraryEntryResolutionError
                let preparationError = resolutionError?.preparationError ?? (error as? PracticePreparationError)
                    ?? .unexpected(stage: "libraryScorePreview", reason: PracticePreparationErrorDetails.safeErrorSummary(error))
                let failure = PracticeLaunchFailure.map(preparationError, entryID: identity.songID, file: resolutionError?.diagnosticFileReference ?? fileReference)
                self.prepared = nil
                pageOwner.clear()
                state = .failure(failure)
                task = nil
                _ = await diagnosticsReporter.record(DiagnosticEvent(
                    severity: .error, code: failure.code, category: .library,
                    stage: "libraryScorePreview", summary: failure.title, reason: PracticePreparationErrorDetails.safeErrorSummary(error),
                    songID: identity.songID, scoreFileVersionID: identity.scoreFileVersionID,
                    persistence: .exportable
                ))
            }
        }
    }

    func close() {
        generation += 1
        task?.cancel()
        task = nil
        identity = nil
        prepared = nil
        pageOwner.clear()
        state = .idle
    }

    private func accepts(_ requestGeneration: Int, isCurrent: @MainActor () -> Bool) -> Bool {
        guard requestGeneration == generation, !Task.isCancelled else { return false }
        guard isCurrent() else {
            close()
            return false
        }
        return true
    }
}
