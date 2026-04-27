import Foundation

enum PianoHighlightParsedElementCoverageCategory: String, Equatable, CaseIterable {
    case consumed
    case derivedConsumed
    case preprocessed
    case metadataOnly
    case explicitlyDeferred
}

struct PianoHighlightParsedElementCoverage: Equatable, Identifiable {
    var id: String { field }

    let field: String
    let category: PianoHighlightParsedElementCoverageCategory
    let reason: String
}

struct PianoHighlightParsedElementCoverageService {
    func allCoverages() -> [PianoHighlightParsedElementCoverage] {
        noteEventCoverages() + scoreCoverages() + noteSpanCoverages()
    }

    func noteEventCoverages() -> [PianoHighlightParsedElementCoverage] {
        [
            coverage("MusicXMLNoteEvent.partID", .derivedConsumed, "Used with staff/voice/tick to correlate source notes and spans."),
            coverage("MusicXMLNoteEvent.measureNumber", .metadataOnly, "Measure identity is preserved for diagnostics; tick drives highlight ordering."),
            coverage("MusicXMLNoteEvent.tick", .consumed, "Guide trigger/release ordering is tick based."),
            coverage("MusicXMLNoteEvent.durationTicks", .derivedConsumed, "Duration contributes to MusicXMLNoteSpan offTick."),
            coverage("MusicXMLNoteEvent.midiNote", .consumed, "Primary key for 2D/3D highlighted piano keys."),
            coverage("MusicXMLNoteEvent.isRest", .consumed, "Rest ticks can produce gap guides."),
            coverage("MusicXMLNoteEvent.isChord", .derivedConsumed, "Same-tick notes are grouped into one trigger guide."),
            coverage("MusicXMLNoteEvent.isGrace", .derivedConsumed, "Grace notes are included or deferred according to expressivity options."),
            coverage("MusicXMLNoteEvent.graceSlash", .derivedConsumed, "Grace scheduling is delegated to existing builders."),
            coverage("MusicXMLNoteEvent.graceStealTimePrevious", .derivedConsumed, "Grace scheduling is delegated to existing builders."),
            coverage("MusicXMLNoteEvent.graceStealTimeFollowing", .derivedConsumed, "Grace scheduling is delegated to existing builders."),
            coverage("MusicXMLNoteEvent.tieStart", .derivedConsumed, "Tie starts are preserved through PracticeStepBuilder and NoteSpanBuilder."),
            coverage("MusicXMLNoteEvent.tieStop", .consumed, "Tie continuation is not emitted as a new trigger."),
            coverage("MusicXMLNoteEvent.staff", .consumed, "Used to avoid collapsing same MIDI notes across staves."),
            coverage("MusicXMLNoteEvent.voice", .consumed, "Used to avoid collapsing same MIDI notes across voices."),
            coverage("MusicXMLNoteEvent.attackTicks", .derivedConsumed, "Performance timing can adjust span onTick."),
            coverage("MusicXMLNoteEvent.releaseTicks", .derivedConsumed, "Performance timing can adjust span offTick."),
            coverage("MusicXMLNoteEvent.dynamicsOverrideVelocity", .derivedConsumed, "Resolved into PracticeStepNote/PianoHighlightNote velocity."),
            coverage("MusicXMLNoteEvent.articulations", .derivedConsumed, "Articulation shortening is reflected through MusicXMLNoteSpanBuilder."),
            coverage("MusicXMLNoteEvent.arpeggiate", .derivedConsumed, "Arpeggiate offsets are reflected through PracticeStepNote.onTickOffset."),
            coverage("MusicXMLNoteEvent.fingeringText", .consumed, "Forwarded to 2D fingering labels."),
        ]
    }

    func scoreCoverages() -> [PianoHighlightParsedElementCoverage] {
        [
            coverage("MusicXMLScore.notes", .consumed, "Source for guide construction and rest/gap detection."),
            coverage("MusicXMLScore.tempoEvents", .metadataOnly, "Tempo affects playback scheduling; guide tick ordering remains tempo independent."),
            coverage("MusicXMLScore.soundDirectives", .preprocessed, "May be materialized by structure expansion and words semantics."),
            coverage("MusicXMLScore.pedalEvents", .explicitlyDeferred, "Pedal sustain is used by audio; visual sustain extension is deferred."),
            coverage("MusicXMLScore.dynamicEvents", .derivedConsumed, "Velocity resolver feeds PracticeStepNote/PianoHighlightNote velocity."),
            coverage("MusicXMLScore.wedgeEvents", .derivedConsumed, "Velocity resolver can consume wedge ramps when enabled."),
            coverage("MusicXMLScore.fermataEvents", .derivedConsumed, "Fermata can affect note spans when enabled."),
            coverage("MusicXMLScore.slurEvents", .metadataOnly, "Slur timeline is preserved for UI/query but does not alter key highlight in this feature."),
            coverage("MusicXMLScore.timeSignatureEvents", .metadataOnly, "Preserved by timelines; not a key highlight input."),
            coverage("MusicXMLScore.keySignatureEvents", .metadataOnly, "Preserved by timelines; not a key highlight input."),
            coverage("MusicXMLScore.clefEvents", .metadataOnly, "Preserved by timelines; not a key highlight input."),
            coverage("MusicXMLScore.wordsEvents", .preprocessed, "Can derive tempo/pedal semantics before guide construction."),
            coverage("MusicXMLScore.measures", .preprocessed, "Used by structure expansion and regression slicing."),
            coverage("MusicXMLScore.repeatDirectives", .preprocessed, "Consumed by structure expansion."),
            coverage("MusicXMLScore.endingDirectives", .preprocessed, "Consumed by structure expansion."),
        ]
    }

    func noteSpanCoverages() -> [PianoHighlightParsedElementCoverage] {
        [
            coverage("MusicXMLNoteSpan.midiNote", .consumed, "Release/off guide is matched by MIDI note."),
            coverage("MusicXMLNoteSpan.staff", .consumed, "Release/off guide is matched by staff."),
            coverage("MusicXMLNoteSpan.voice", .consumed, "Release/off guide is matched by voice."),
            coverage("MusicXMLNoteSpan.onTick", .consumed, "Correlates trigger notes with spans."),
            coverage("MusicXMLNoteSpan.offTick", .consumed, "Drives release/gap guides."),
        ]
    }

    private func coverage(
        _ field: String,
        _ category: PianoHighlightParsedElementCoverageCategory,
        _ reason: String
    ) -> PianoHighlightParsedElementCoverage {
        PianoHighlightParsedElementCoverage(field: field, category: category, reason: reason)
    }
}
