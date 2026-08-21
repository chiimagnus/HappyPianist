import Foundation
import MusicXML
import Practice
import simd

enum PianoDemonstrationHandsTiming {
    case transport(PianoDemonstrationTransportTiming)
    case transportPending
    case manual
}

struct PianoDemonstrationTransportTiming: Equatable {
    let generation: Int
    let playbackPositionSeconds: TimeInterval
    let capturedAt: PerformanceMonotonicInstant
    let isPaused: Bool
    let playbackRate: Double
    let timeSchedule: AutoplayTimelineTimeSchedule
    let contactTimeline: PianoKeyContactTimeline
    let guides: [PianoHighlightGuide]

    func playbackPosition(at instant: PerformanceMonotonicInstant) -> TimeInterval {
        guard isPaused == false else { return playbackPositionSeconds }
        return max(0, playbackPositionSeconds + (instant.seconds - capturedAt.seconds) * playbackRate)
    }
}

/// Samples only clips whose generation belongs to the current audio transport.
struct PianoHandMotionPlayer {
    struct Sample: Equatable {
        let hand: ScoreHand
        let frame: PianoHandMotionClip.Frame
        let activeMIDINotes: Set<Int>
    }

    func samples(
        clipSet: PianoDemonstrationMotionClipSet,
        timing: PianoDemonstrationHandsTiming,
        at instant: PerformanceMonotonicInstant
    ) -> [Sample] {
        guard case let .transport(transport) = timing,
              clipSet.transportGeneration == transport.generation
        else {
            return []
        }
        let playbackSeconds = transport.playbackPosition(at: instant)
        return clipSet.clips.compactMap { clip in
            sample(
                clip: clip,
                playbackSeconds: playbackSeconds,
                contactTimeline: transport.contactTimeline
            )
        }
    }

    private func sample(
        clip: PianoHandMotionClip,
        playbackSeconds: TimeInterval,
        contactTimeline: PianoKeyContactTimeline
    ) -> Sample? {
        guard let firstFrame = clip.frames.first,
              let lastRelease = clip.coverage.map(\.releaseSeconds).max(),
              playbackSeconds >= firstFrame.timeSeconds,
              playbackSeconds <= lastRelease
        else {
            return nil
        }
        let activeMIDINotes: Set<Int> = Set(clip.coverage.compactMap { coverage in
            guard coverage.onsetSeconds <= playbackSeconds,
                  playbackSeconds <= coverage.releaseSeconds
            else {
                return nil
            }
            return contactTimeline.contact(forOccurrenceID: coverage.occurrenceID)?.midiNote
        })
        return Sample(
            hand: clip.hand,
            frame: interpolatedFrame(in: clip, at: playbackSeconds),
            activeMIDINotes: activeMIDINotes
        )
    }

    private func interpolatedFrame(
        in clip: PianoHandMotionClip,
        at playbackSeconds: TimeInterval
    ) -> PianoHandMotionClip.Frame {
        guard let first = clip.frames.first, let last = clip.frames.last else {
            return clip.frame(at: playbackSeconds)
        }
        guard playbackSeconds > first.timeSeconds, playbackSeconds < last.timeSeconds else {
            return playbackSeconds >= last.timeSeconds ? last : first
        }
        var upperIndex = 1
        while clip.frames[upperIndex].timeSeconds < playbackSeconds {
            upperIndex += 1
        }
        let lower = clip.frames[upperIndex - 1]
        let upper = clip.frames[upperIndex]
        let duration = upper.timeSeconds - lower.timeSeconds
        guard duration > 0 else { return upper }
        let progress = Float((playbackSeconds - lower.timeSeconds) / duration)
        return .init(
            timeSeconds: playbackSeconds,
            rootTransform: .init(
                translation: simd_mix(
                    lower.rootTransform.translation,
                    upper.rootTransform.translation,
                    SIMD3(repeating: progress)
                ),
                rotation: simd_slerp(
                    simd_quatf(vector: lower.rootTransform.rotation),
                    simd_quatf(vector: upper.rootTransform.rotation),
                    progress
                ).vector
            ),
            jointRotations: zip(lower.jointRotations, upper.jointRotations).map { lower, upper in
                simd_slerp(simd_quatf(vector: lower), simd_quatf(vector: upper), progress).vector
            }
        )
    }
}
