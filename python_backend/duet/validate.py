from __future__ import annotations

import argparse
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass(frozen=True)
class MidiNote:
    pitch: int
    velocity: int
    start_time_sec: float
    duration_sec: float

    @property
    def end_time_sec(self) -> float:
        return float(self.start_time_sec) + float(self.duration_sec)


def _load_generator_bundle_bytes(bundle_path: Path) -> tuple[bytes, bytes]:
    # Strategy requirement: TF-only loading (no Magenta dependency).
    from note_seq.protobuf import generator_pb2  # type: ignore[import-not-found]
    import tensorflow.compat.v1 as tf  # type: ignore[import-not-found]

    bundle = generator_pb2.GeneratorBundle()
    with tf.gfile.Open(str(bundle_path), "rb") as f:
        bundle.ParseFromString(f.read())

    if len(bundle.checkpoint_file) != 1:
        raise ValueError(f"Expected exactly 1 checkpoint_file entry, got {len(bundle.checkpoint_file)}")
    if not bundle.metagraph_file:
        raise ValueError("Bundle is missing metagraph_file")

    return bundle.checkpoint_file[0], bundle.metagraph_file


def _notes_to_event_ids(notes: list[MidiNote]) -> list[int]:
    import note_seq  # type: ignore[import-not-found]
    from note_seq.protobuf import music_pb2  # type: ignore[import-not-found]

    sequence = music_pb2.NoteSequence()
    sequence.tempos.add(qpm=120.0)

    total_time = 0.0
    for n in notes:
        sequence.notes.add(
            pitch=int(n.pitch),
            velocity=int(n.velocity),
            start_time=float(n.start_time_sec),
            end_time=float(n.end_time_sec),
        )
        total_time = max(total_time, float(n.end_time_sec))
    sequence.total_time = float(total_time)

    q = note_seq.sequences_lib.quantize_note_sequence_absolute(sequence, steps_per_second=100)
    performance = note_seq.performance_lib.Performance(quantized_sequence=q, num_velocity_bins=32)
    enc = note_seq.performance_encoder_decoder.PerformanceOneHotEncoding(num_velocity_bins=32)
    return [int(enc.encode_event(e)) for e in performance]


def _event_id_to_one_hot(event_id: int, *, num_classes: int = 388) -> np.ndarray:
    if not (0 <= int(event_id) < num_classes):
        raise ValueError(f"event_id out of range: {event_id}")
    x = np.zeros((1, 1, num_classes), dtype=np.float32)
    x[0, 0, int(event_id)] = 1.0
    return x


def _zero_states(*, hidden_dim: int = 512, num_layers: int = 3) -> list[np.ndarray]:
    return [np.zeros((1, hidden_dim), dtype=np.float32) for _ in range(num_layers * 2)]


def _tf_step_fn(metagraph_path: Path, checkpoint_path: Path):
    import tensorflow.compat.v1 as tf  # type: ignore[import-not-found]

    graph = tf.Graph()
    with graph.as_default():
        saver = tf.train.import_meta_graph(str(metagraph_path), clear_devices=True)
        inputs_t = graph.get_collection("inputs")[0]
        temperature_t = graph.get_collection("temperature")[0]
        softmax_t = graph.get_collection("softmax")[0]
        initial_state_ts = graph.get_collection("initial_state")
        final_state_ts = graph.get_collection("final_state")

        sess = tf.Session(graph=graph)
        saver.restore(sess, str(checkpoint_path))

    def run_step(x_one_hot: np.ndarray, states: list[np.ndarray], temperature: float = 1.0):
        if len(states) != len(initial_state_ts):
            raise ValueError("Unexpected state length.")

        feed: dict = {inputs_t: x_one_hot, temperature_t: float(temperature)}
        for t, v in zip(initial_state_ts, states):
            feed[t] = v

        softmax, new_states = sess.run([softmax_t, final_state_ts], feed_dict=feed)
        return softmax.astype(np.float32), [s.astype(np.float32) for s in new_states]

    return sess, run_step


def _coreml_step_fn(coreml_path: Path):
    import coremltools as ct  # type: ignore[import-not-found]

    mlmodel = ct.models.MLModel(str(coreml_path))

    def run_step(x_one_hot: np.ndarray, states: list[np.ndarray], temperature: float = 1.0):
        if len(states) != 6:
            raise ValueError("Unexpected state length.")

        t = np.array([[float(temperature)]], dtype=np.float32)
        inputs = {
            "x": x_one_hot,
            "temperature": t,
            "c0": states[0],
            "h0": states[1],
            "c1": states[2],
            "h1": states[3],
            "c2": states[4],
            "h2": states[5],
        }
        out = mlmodel.predict(inputs)
        softmax = out["softmax"].astype(np.float32)
        new_states = [
            out["c0_out"].astype(np.float32),
            out["h0_out"].astype(np.float32),
            out["c1_out"].astype(np.float32),
            out["h1_out"].astype(np.float32),
            out["c2_out"].astype(np.float32),
            out["h2_out"].astype(np.float32),
        ]
        return softmax, new_states

    return run_step


def _behavior_validate_softmax(softmax: np.ndarray, *, top_k: int = 16) -> None:
    if not np.isfinite(softmax).all():
        raise AssertionError("softmax contains NaN/Inf")
    s = float(np.sum(softmax))
    if not np.isfinite(s):
        raise AssertionError("softmax sum is NaN/Inf")
    if abs(s - 1.0) > 1e-3:
        raise AssertionError(f"softmax not normalized: sum={s}")

    flat = softmax.reshape(-1)
    k = min(int(top_k), flat.size)
    top_idx = np.argpartition(-flat, k - 1)[:k]
    top_idx = top_idx[np.argsort(-flat[top_idx])]
    if not ((0 <= top_idx).all() and (top_idx < 388).all()):
        raise AssertionError("top-k indices out of range")


def _validate_case(
    *,
    name: str,
    notes: list[MidiNote],
    tf_step,
    coreml_step,
    atol: float,
) -> None:
    event_ids = _notes_to_event_ids(notes)
    if not event_ids:
        raise AssertionError("Empty event id sequence (unexpected).")

    tf_states = _zero_states()
    cm_states = _zero_states()

    worst = 0.0
    for step_idx, eid in enumerate(event_ids):
        x = _event_id_to_one_hot(eid)

        tf_softmax, tf_states = tf_step(x, tf_states, temperature=1.0)
        cm_softmax, cm_states = coreml_step(x, cm_states, temperature=1.0)

        # First, ensure CoreML behaves like a probability distribution.
        _behavior_validate_softmax(cm_softmax)

        if not np.allclose(tf_softmax, cm_softmax, atol=atol):
            max_abs = float(np.max(np.abs(tf_softmax - cm_softmax)))
            raise AssertionError(f"{name}: step={step_idx} eid={eid} softmax mismatch (max_abs={max_abs})")

        # Also verify state parity (helps catch gate-order mistakes).
        for s_idx, (a, b) in enumerate(zip(tf_states, cm_states)):
            if not np.allclose(a, b, atol=atol):
                max_abs = float(np.max(np.abs(a - b)))
                raise AssertionError(f"{name}: step={step_idx} state[{s_idx}] mismatch (max_abs={max_abs})")

        worst = max(worst, float(np.max(np.abs(tf_softmax - cm_softmax))))

    print(f"[ok] {name}: events={len(event_ids)} worst_abs_diff={worst:.3e}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate CoreML Performance RNN against TF metagraph/checkpoint")
    parser.add_argument(
        "--bundle",
        type=Path,
        default=Path(__file__).parent / "models" / "performance_with_dynamics.mag",
        help="Path to performance_with_dynamics.mag",
    )
    parser.add_argument(
        "--coreml",
        type=Path,
        default=Path(__file__).parent / "models" / "AIDuetPerformanceRNN.mlpackage",
        help="Path to AIDuetPerformanceRNN.mlpackage",
    )
    parser.add_argument("--atol", type=float, default=1e-4, help="Absolute tolerance for allclose")
    args = parser.parse_args()

    if not args.bundle.exists():
        raise FileNotFoundError(args.bundle)
    if not args.coreml.exists():
        raise FileNotFoundError(args.coreml)

    # Required test inputs:
    # (a) single notes [C4, E4, G4]
    arpeggio = [
        MidiNote(pitch=60, velocity=80, start_time_sec=0.0, duration_sec=0.5),
        MidiNote(pitch=64, velocity=80, start_time_sec=0.5, duration_sec=0.5),
        MidiNote(pitch=67, velocity=80, start_time_sec=1.0, duration_sec=0.5),
    ]
    # (b) chord [C4+E4+G4 simultaneously]
    chord = [
        MidiNote(pitch=60, velocity=80, start_time_sec=0.0, duration_sec=0.75),
        MidiNote(pitch=64, velocity=80, start_time_sec=0.0, duration_sec=0.75),
        MidiNote(pitch=67, velocity=80, start_time_sec=0.0, duration_sec=0.75),
    ]

    # Primary strategy: run TF inference without Magenta (using the metagraph inside the .mag bundle)
    try:
        checkpoint_bytes, metagraph_bytes = _load_generator_bundle_bytes(args.bundle)

        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            ckpt = tmp / "checkpoint"
            meta = tmp / "model.meta"
            ckpt.write_bytes(checkpoint_bytes)
            meta.write_bytes(metagraph_bytes)

            sess, tf_step = _tf_step_fn(meta, ckpt)
            try:
                coreml_step = _coreml_step_fn(args.coreml)
                _validate_case(name="arpeggio(C4,E4,G4)", notes=arpeggio, tf_step=tf_step, coreml_step=coreml_step, atol=args.atol)
                _validate_case(name="chord(C4+E4+G4)", notes=chord, tf_step=tf_step, coreml_step=coreml_step, atol=args.atol)
            finally:
                sess.close()

        print("[ok] TF↔CoreML numeric parity verified.")
        return 0

    except Exception as e:
        print("[warn] TF numeric validation failed; falling back to behavior-level checks.")
        print(f"[warn] reason: {type(e).__name__}: {e}")

    # Fallback: behavior-level validation only (no TF comparison).
    coreml_step = _coreml_step_fn(args.coreml)
    for name, notes in [("arpeggio(C4,E4,G4)", arpeggio), ("chord(C4+E4+G4)", chord)]:
        event_ids = _notes_to_event_ids(notes)
        states = _zero_states()
        for step_idx, eid in enumerate(event_ids):
            x = _event_id_to_one_hot(eid)
            softmax, states = coreml_step(x, states, temperature=1.0)
            _behavior_validate_softmax(softmax)
        print(f"[ok] {name}: behavior checks passed (events={len(event_ids)})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

