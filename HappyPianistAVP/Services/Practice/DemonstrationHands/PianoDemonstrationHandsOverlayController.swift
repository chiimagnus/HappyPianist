import Diagnostics
import Foundation
import Practice
import RealityKit
import simd
import SwiftUI

@MainActor
final class PianoDemonstrationHandsOverlayController {
    private enum StrokeTimingIdentity: Equatable {
        case manual
        case transportPending
        case transport(Int)
    }

    private struct HandStrokeRuntime {
        struct Occurrence {
            let target: PianoDemonstrationHandTarget
            let schedule: PianoDemonstrationStrikeScheduler.Occurrence
        }

        var occurrences: [String: Occurrence] = [:]
        var timingIdentity: StrokeTimingIdentity?
    }

    private let rootEntity: Entity
    private let diagnosticsReporter: (any DiagnosticsReporting)?
    private let rigLoader: any PianoDemonstrationHandRigLoading
    private let performanceClock: PerformanceClock
    private let suppressionMinimumResidence: TimeInterval
    private let targetResolver = PianoDemonstrationHandTargetResolver()
    private let poseResolver = PianoDemonstrationHandPoseResolver()
    private let strikeScheduler: PianoDemonstrationStrikeScheduler
    private var rigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]
    private var lastResolvedCoverage = PianoDemonstrationHandCoverage()
    private var lastCoverage = PianoDemonstrationHandCoverage()
    private var activeMIDINotesByHand: [PianoDemonstrationHand: Set<Int>] = [:]
    private var suppressionExpiryByMIDINote: [Int: PerformanceMonotonicInstant] = [:]
    private var strokeRuntimeByHand: [PianoDemonstrationHand: HandStrokeRuntime] = [:]
    private var lastSubmittedPalmCenterByHand: [PianoDemonstrationHand: SIMD3<Float>] = [:]
    private var loadTask: Task<Void, Never>?
    private var hasReportedManualTimingFallback = false
    private var hasAttachedRoot = false
    private var reduceMotionEnabled = false
    private(set) var requiresReplacement = false

    init(
        rootEntity: Entity = Entity(),
        diagnosticsReporter: (any DiagnosticsReporting)? = nil,
        preloadedRigs: [PianoDemonstrationHand: PianoDemonstrationHandRig]? = nil,
        rigLoader: any PianoDemonstrationHandRigLoading = PackagedPianoDemonstrationHandRigLoader(),
        performanceClock: PerformanceClock = .live(),
        suppressionMinimumResidence: TimeInterval = 0.12
    ) {
        self.rootEntity = rootEntity
        self.diagnosticsReporter = diagnosticsReporter
        self.rigLoader = rigLoader
        self.performanceClock = performanceClock
        self.strikeScheduler = PianoDemonstrationStrikeScheduler(performanceClock: performanceClock)
        self.suppressionMinimumResidence = max(0, suppressionMinimumResidence)
        rigs = preloadedRigs ?? [:]
        for (hand, rig) in rigs {
            install(rig: rig, for: hand)
        }
        if preloadedRigs == nil {
            startLoadingRigs()
        }
    }

    @discardableResult
    func update(
        isEnabled: Bool,
        highlightGuide: PianoHighlightGuide?,
        timing: PianoDemonstrationHandsTiming,
        keyboardGeometry: PianoKeyboardGeometry?,
        reduceMotion: Bool,
        content: RealityViewContent?
    ) -> Set<Int> {
        guard requiresReplacement == false, isEnabled, let keyboardGeometry else {
            hide()
            return []
        }

        if let content {
            attachRootIfNeeded(to: content)
        }
        rootEntity.transform = Transform(matrix: keyboardGeometry.frame.worldFromKeyboard)

        let now = performanceClock.now()
        let presentationGuide = presentationGuide(
            current: highlightGuide,
            timing: timing,
            keyboardGeometry: keyboardGeometry,
            at: now
        )
        let resolvedCoverage = targetResolver.resolve(
            highlightGuide: presentationGuide,
            keyboardGeometry: keyboardGeometry
        )
        lastResolvedCoverage = resolvedCoverage
        let coverage = resolvedCoverage.limitedToAvailableHands(Set(rigs.keys))
        reduceMotionEnabled = reduceMotion
        lastCoverage = coverage

        if reduceMotion {
            resetAllStrokeRuntimes()
            let unreachableOccurrenceIDs = applyCurrentTargets(at: now)
            lastCoverage = lastCoverage.markingUnreachable(occurrenceIDs: unreachableOccurrenceIDs)
            return currentSuppressedMIDINotes()
        }

        for hand in PianoDemonstrationHand.allCases {
            let targetsForHand = coverage.coveredTargets(for: hand)
            updateStrokeRuntime(
                for: hand,
                targets: targetsForHand,
                timing: timing,
                at: now
            )
            let unreachableOccurrenceIDs = applyCurrentTargets(hand: hand, at: now)
            lastCoverage = lastCoverage.markingUnreachable(occurrenceIDs: unreachableOccurrenceIDs)
        }
        return currentSuppressedMIDINotes()
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        resetAllStrokeRuntimes()
        rootEntity.stopAllAnimations()
        for rig in rigs.values {
            rig.hide()
        }
        rigs.removeAll()
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByMIDINote.removeAll()
        lastSubmittedPalmCenterByHand.removeAll()
        lastResolvedCoverage = PianoDemonstrationHandCoverage()
        lastCoverage = PianoDemonstrationHandCoverage()
        reduceMotionEnabled = false
        hasReportedManualTimingFallback = false
        rootEntity.children.removeAll(preservingWorldTransforms: false)
        rootEntity.removeFromParent()
        hasAttachedRoot = false
        requiresReplacement = true
    }

    private func startLoadingRigs() {
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { loadTask = nil }
            for hand in PianoDemonstrationHand.allCases {
                guard Task.isCancelled == false else { return }
                do {
                    let rig = try await rigLoader.load(hand: hand)
                    guard Task.isCancelled == false, requiresReplacement == false else { return }
                    install(rig: rig, for: hand)
                    lastCoverage = lastResolvedCoverage.limitedToAvailableHands(Set(rigs.keys))
                    let unreachableOccurrenceIDs = applyCurrentTargets(
                        hand: hand,
                        at: performanceClock.now()
                    )
                    lastCoverage = lastCoverage.markingUnreachable(
                        occurrenceIDs: unreachableOccurrenceIDs
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard Task.isCancelled == false else { return }
                    lastCoverage = lastResolvedCoverage.limitedToAvailableHands(Set(rigs.keys))
                    diagnosticsReporter?.recordSystem(
                        severity: .error,
                        category: .immersiveSpace,
                        stage: "pianoDemonstrationHands.loadAsset",
                        summary: "演示手资源加载失败",
                        reason: "hand=\(hand), reason=assetUnavailable, error=\(String(describing: type(of: error)))"
                    )
                }
            }
        }
    }

    private func install(rig: PianoDemonstrationHandRig, for hand: PianoDemonstrationHand) {
        rig.rootEntity.name = "pianoDemonstrationHand.\(hand)"
        rootEntity.addChild(rig.rootEntity)
        rigs[hand] = rig
    }

    private func presentationGuide(
        current: PianoHighlightGuide?,
        timing: PianoDemonstrationHandsTiming,
        keyboardGeometry: PianoKeyboardGeometry,
        at now: PerformanceMonotonicInstant
    ) -> PianoHighlightGuide? {
        guard case let .transport(transport) = timing else { return current }
        let playbackPosition = transport.playbackPosition(at: now)
        let scheduledEvents = transport.timeSchedule.scheduledCursorEvents
        let earliestRelevantTime = playbackPosition - PianoDemonstrationStrikeScheduler.maximumPreRollDuration
        var low = 0
        var high = scheduledEvents.count
        while low < high {
            let middle = (low + high) / 2
            if scheduledEvents[middle].timeSeconds < earliestRelevantTime {
                low = middle + 1
            } else {
                high = middle
            }
        }

        var activeByOccurrenceID = Dictionary(
            uniqueKeysWithValues: (current?.activeNotes ?? []).map { ($0.occurrenceID, $0) }
        )
        var triggeredByOccurrenceID = Dictionary(
            uniqueKeysWithValues: (current?.triggeredNotes ?? []).map { ($0.occurrenceID, $0) }
        )
        var presentationMetadata = current
        var index = low
        while index < scheduledEvents.count {
            let scheduledEvent = scheduledEvents[index]
            if scheduledEvent.timeSeconds > playbackPosition + PianoDemonstrationStrikeScheduler.maximumPreRollDuration {
                break
            }
            defer { index += 1 }
            guard case let .guide(guideIndex, _) = scheduledEvent.event,
                  transport.guides.indices.contains(guideIndex)
            else {
                continue
            }
            let upcoming = transport.guides[guideIndex]
            guard upcoming.triggeredNotes.isEmpty == false else { continue }
            let upcomingCoverage = targetResolver.resolve(
                highlightGuide: upcoming,
                keyboardGeometry: keyboardGeometry
            )
            let travelDistanceByHand = Dictionary(
                uniqueKeysWithValues: PianoDemonstrationHand.allCases.map { hand in
                    (hand, handTravelDistance(for: hand, targets: upcomingCoverage.coveredTargets(for: hand)))
                }
            )

            for target in upcomingCoverage.coveredTargets where target.phase == .triggered {
                guard let onsetSeconds = transport.timeSchedule.noteOnTimeSeconds(
                    forSourceEventID: target.occurrenceID
                ) else {
                    continue
                }
                let preRoll = strikeScheduler.preRollDuration(
                    velocity: target.velocity,
                    handTravelDistanceMeters: travelDistanceByHand[target.hand] ?? 0
                )
                guard playbackPosition >= onsetSeconds - preRoll else { continue }
                guard let note = upcoming.triggeredNotes.first(where: {
                    $0.occurrenceID == target.occurrenceID
                }) else {
                    continue
                }
                activeByOccurrenceID[target.occurrenceID] = nil
                triggeredByOccurrenceID[target.occurrenceID] = note
                presentationMetadata = upcoming
            }
        }

        guard let metadata = presentationMetadata ?? transport.guides.first,
              activeByOccurrenceID.isEmpty == false || triggeredByOccurrenceID.isEmpty == false
        else {
            return current
        }
        return PianoHighlightGuide(
            id: metadata.id,
            kind: triggeredByOccurrenceID.isEmpty ? metadata.kind : .trigger,
            tick: metadata.tick,
            durationTicks: metadata.durationTicks,
            practiceStepIndex: metadata.practiceStepIndex,
            activeNotes: activeByOccurrenceID.values.sorted { $0.occurrenceID < $1.occurrenceID },
            triggeredNotes: triggeredByOccurrenceID.values.sorted { $0.occurrenceID < $1.occurrenceID },
            releasedMIDINotes: current?.releasedMIDINotes ?? []
        )
    }

    private func updateStrokeRuntime(
        for hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget],
        timing: PianoDemonstrationHandsTiming,
        at now: PerformanceMonotonicInstant
    ) {
        let triggeredTargets = targets.filter { $0.phase == .triggered }
        var runtime = strokeRuntime(for: hand)
        let timingIdentity: StrokeTimingIdentity = switch timing {
        case .manual: .manual
        case .transportPending: .transportPending
        case let .transport(transport): .transport(transport.generation)
        }
        if runtime.timingIdentity != timingIdentity {
            runtime.occurrences.removeAll()
            runtime.timingIdentity = timingIdentity
        }

        let handTravelDistance = handTravelDistance(for: hand, targets: triggeredTargets)
        for target in triggeredTargets where runtime.occurrences[target.occurrenceID] == nil {
            let schedule: PianoDemonstrationStrikeScheduler.Occurrence?
            switch timing {
            case let .transport(transport):
                schedule = makeTransportOccurrence(
                    hand: hand,
                    target: target,
                    handTravelDistanceMeters: handTravelDistance,
                    timing: transport
                )
            case .transportPending:
                schedule = nil
            case .manual:
                schedule = makeManualOccurrence(
                    hand: hand,
                    target: target,
                    handTravelDistanceMeters: handTravelDistance,
                    at: now
                )
                reportManualTimingIfNeeded(reason: "transportUnavailable")
            }
            if let schedule {
                runtime.occurrences[target.occurrenceID] = .init(target: target, schedule: schedule)
            }
        }

        let currentlyPresentedOccurrenceIDs = Set(targets.map(\.occurrenceID))
        runtime.occurrences = runtime.occurrences.filter { occurrenceID, occurrence in
            currentlyPresentedOccurrenceIDs.contains(occurrenceID)
                || strikeScheduler.sample(occurrence.schedule, at: now).isComplete == false
        }
        strokeRuntimeByHand[hand] = runtime
    }

    private func makeTransportOccurrence(
        hand: PianoDemonstrationHand,
        target: PianoDemonstrationHandTarget,
        handTravelDistanceMeters: Float,
        timing: PianoDemonstrationTransportTiming
    ) -> PianoDemonstrationStrikeScheduler.Occurrence? {
        guard let onsetSeconds = timing.timeSchedule.noteOnTimeSeconds(
            forSourceEventID: target.occurrenceID
        ), let releaseSeconds = timing.timeSchedule.noteOffTimeSeconds(
            forSourceEventID: target.occurrenceID
        ) else {
            return nil
        }
        return PianoDemonstrationStrikeScheduler.Occurrence(
            id: target.occurrenceID,
            hand: hand,
            onset: timing.performanceInstant(atPlaybackSeconds: onsetSeconds),
            release: timing.performanceInstant(atPlaybackSeconds: max(onsetSeconds, releaseSeconds)),
            velocity: target.velocity,
            handTravelDistanceMeters: handTravelDistanceMeters
        )
    }

    private func makeManualOccurrence(
        hand: PianoDemonstrationHand,
        target: PianoDemonstrationHandTarget,
        handTravelDistanceMeters: Float,
        at now: PerformanceMonotonicInstant
    ) -> PianoDemonstrationStrikeScheduler.Occurrence {
        let onset = now.advanced(by: strikeScheduler.preRollDuration(
            velocity: target.velocity,
            handTravelDistanceMeters: handTravelDistanceMeters
        ))
        return PianoDemonstrationStrikeScheduler.Occurrence(
            id: target.occurrenceID,
            hand: hand,
            onset: onset,
            release: onset,
            velocity: target.velocity,
            handTravelDistanceMeters: handTravelDistanceMeters
        )
    }

    private func reportManualTimingIfNeeded(reason: String) {
        guard hasReportedManualTimingFallback == false else { return }
        hasReportedManualTimingFallback = true
        diagnosticsReporter?.recordSystem(
            severity: .warning,
            category: .immersiveSpace,
            stage: "pianoDemonstrationHands.timing",
            summary: "示范手使用未对齐的手动时序",
            reason: "mode=manual;reason=\(reason)"
        )
    }

    private func resetAllStrokeRuntimes() {
        strokeRuntimeByHand.removeAll()
    }

    private func strokeRuntime(for hand: PianoDemonstrationHand) -> HandStrokeRuntime {
        strokeRuntimeByHand[hand] ?? HandStrokeRuntime()
    }

    @discardableResult
    private func applyCurrentTargets(
        hand selectedHand: PianoDemonstrationHand? = nil,
        at now: PerformanceMonotonicInstant
    ) -> Set<String> {
        var unreachableOccurrenceIDs = Set<String>()
        for hand in PianoDemonstrationHand.allCases where selectedHand == nil || selectedHand == hand {
            let runtime = strokeRuntime(for: hand)
            var targetsByOccurrenceID = Dictionary(
                uniqueKeysWithValues: lastCoverage.coveredTargets(for: hand).map { ($0.occurrenceID, $0) }
            )
            for (occurrenceID, occurrence) in runtime.occurrences
                where targetsByOccurrenceID[occurrenceID] == nil
                    && strikeScheduler.sample(occurrence.schedule, at: now).isComplete == false
            {
                targetsByOccurrenceID[occurrenceID] = occurrence.target
            }
            let targetsForHand = targetsByOccurrenceID.values.sorted { $0.occurrenceID < $1.occurrenceID }
            let strikeProgressByOccurrenceID = Dictionary(
                uniqueKeysWithValues: runtime.occurrences.map {
                    ($0.key, strikeScheduler.sample($0.value.schedule, at: now).contactProgress)
                }
            )
            let resolution = poseResolver.resolve(
                hand: hand,
                targets: targetsForHand,
                strikeProgressByOccurrenceID: strikeProgressByOccurrenceID
            )
            let failedOccurrenceIDs = Set(resolution.unreachableOccurrences.map(\.occurrenceID))
            unreachableOccurrenceIDs.formUnion(failedOccurrenceIDs)
            let submittedTargets = targetsForHand.filter {
                resolution.reachableOccurrenceIDs.contains($0.occurrenceID)
            }
            if let pose = resolution.pose, let rig = rigs[hand] {
                rig.apply(pose: pose)
                activeMIDINotesByHand[hand] = Set(submittedTargets.map(\.midiNote))
                lastSubmittedPalmCenterByHand[hand] = pose.palmCenterLocal
            } else if shouldLift(hand: hand, releasedMIDINotes: lastCoverage.releasedMIDINotes) {
                rigs[hand]?.lift(animated: reduceMotionEnabled == false)
                activeMIDINotesByHand[hand] = []
            } else {
                rigs[hand]?.hide()
                activeMIDINotesByHand[hand] = []
            }
        }
        return unreachableOccurrenceIDs
    }

    private func handTravelDistance(
        for hand: PianoDemonstrationHand,
        targets: [PianoDemonstrationHandTarget]
    ) -> Float {
        guard let previousPalmCenter = lastSubmittedPalmCenterByHand[hand],
              let nextPalmCenter = poseResolver.resolve(hand: hand, targets: targets).pose?.palmCenterLocal
        else {
            return 0
        }
        return simd_distance(previousPalmCenter, nextPalmCenter)
    }

    private func currentSuppressedMIDINotes() -> Set<Int> {
        let now = performanceClock.now()
        let activeMIDINotes = activeMIDINotesByHand.values.reduce(into: Set<Int>()) {
            $0.formUnion($1)
        }
        for midiNote in activeMIDINotes {
            suppressionExpiryByMIDINote[midiNote] = now.advanced(by: suppressionMinimumResidence)
        }
        let expiredMIDINotes = suppressionExpiryByMIDINote.compactMap { midiNote, expiry in
            activeMIDINotes.contains(midiNote) == false && expiry <= now ? midiNote : nil
        }
        for midiNote in expiredMIDINotes {
            suppressionExpiryByMIDINote[midiNote] = nil
        }
        return Set(suppressionExpiryByMIDINote.keys)
    }

    private func attachRootIfNeeded(to content: RealityViewContent) {
        guard hasAttachedRoot == false else { return }
        content.add(rootEntity)
        hasAttachedRoot = true
    }

    private func shouldLift(
        hand: PianoDemonstrationHand,
        releasedMIDINotes: Set<Int>
    ) -> Bool {
        guard let activeMIDINotes = activeMIDINotesByHand[hand], activeMIDINotes.isEmpty == false else {
            return false
        }
        return activeMIDINotes.isDisjoint(with: releasedMIDINotes) == false
    }

    private func hide() {
        resetAllStrokeRuntimes()
        for rig in rigs.values {
            rig.hide()
        }
        activeMIDINotesByHand.removeAll()
        suppressionExpiryByMIDINote.removeAll()
        lastSubmittedPalmCenterByHand.removeAll()
        lastResolvedCoverage = PianoDemonstrationHandCoverage()
        lastCoverage = PianoDemonstrationHandCoverage()
        reduceMotionEnabled = false
        hasReportedManualTimingFallback = false
        rootEntity.removeFromParent()
        hasAttachedRoot = false
    }
}
