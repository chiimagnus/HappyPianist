from __future__ import annotations

import argparse
import sys
from pathlib import Path
import json

sys.path.append(str(Path(__file__).resolve().parents[1]))

from server.media.midi_generation import (
    MidiAnalysis,
    NoteEvent,
    generate_expanded_midi,
    parse_midi_file,
    summarize_analysis,
    write_midi,
    write_continuation_midi,
)
from server.media.musicxml_generation import write_musicxml


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Parse a source MIDI file, extract musical features, and generate an expanded MIDI output."
    )
    parser.add_argument("input_midi", type=Path, help="Input MIDI file to analyze")
    parser.add_argument("output_midi", type=Path, help="Output MIDI file path")
    parser.add_argument(
        "--mode",
        choices=["continue", "accompaniment", "variation", "emotion"],
        default="variation",
        help="Generation mode for the expanded music",
    )
    parser.add_argument(
        "--analysis-json",
        type=Path,
        default=None,
        help="Optional JSON file to write extracted MIDI features",
    )
    parser.add_argument(
        "--extra-duration",
        type=float,
        default=20.0,
        help="Extra generated music length in seconds (default: 20)",
    )
    parser.add_argument(
        "--output-musicxml",
        type=Path,
        default=None,
        help="Output MusicXML file path (optional)",
    )
    parser.add_argument(
        "--no-source",
        action="store_true",
        help="Only output generated music, not the original source",
    )
    parser.add_argument(
        "--continuation-output",
        type=Path,
        default=None,
        help="Separate output file for continuation-only MIDI (time starts at 0)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Random seed for melody generation (default: random each run)",
    )
    args = parser.parse_args()

    source_notes, analysis = parse_midi_file(args.input_midi)
    melody, accompaniment = generate_expanded_midi(
        source_notes, analysis, mode=args.mode, extra_duration=args.extra_duration, include_source=not args.no_source, seed=args.seed
    )
    write_midi(melody, accompaniment, analysis, args.output_midi)

    # Write continuation-only file if requested
    if args.continuation_output is not None:
        cont_melody, cont_accompaniment = generate_expanded_midi(
            source_notes, analysis, mode=args.mode, extra_duration=args.extra_duration, include_source=False, seed=args.seed
        )
        write_continuation_midi(cont_melody, cont_accompaniment, analysis, args.continuation_output)
        print(f"Wrote continuation-only MIDI: {args.continuation_output}")

    # Generate MusicXML if requested
    if args.output_musicxml:
        title = args.input_midi.stem + "_generated"
        write_musicxml(melody, accompaniment, analysis, args.output_musicxml, title=title)

    output: dict[str, object] = {
        "input_midi": str(args.input_midi),
        "output_midi": str(args.output_midi),
        "mode": args.mode,
        "analysis": summarize_analysis(analysis),
        "source_note_count": len(source_notes),
        "generated_melody_count": len(melody) - (len(source_notes) if not args.no_source else 0),
        "generated_accompaniment_count": len(accompaniment),
    }
    print(json.dumps(output, indent=2, ensure_ascii=False))

    if args.analysis_json is not None:
        args.analysis_json.parent.mkdir(parents=True, exist_ok=True)
        args.analysis_json.write_text(json.dumps(summarize_analysis(analysis), indent=2, ensure_ascii=False))
        print(f"Wrote analysis JSON: {args.analysis_json}")


if __name__ == "__main__":
    main()
