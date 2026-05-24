from __future__ import annotations

import os
import threading
import time

from api.protocol import DialogueNote, GenerateParams, legalize_notes
from .inference_engine_protocol import InferenceEngineProtocol
from .note_conversion import dialogue_notes_to_note_sequence, note_sequence_to_dialogue_notes


class MagentaPerformanceRNNEngine(InferenceEngineProtocol):
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._generator = None
        self._load_ms: int | None = None
        self._bundle_file: str | None = None
        self._model_name: str | None = None
        self._ensure_loaded()

    @property
    def model_name(self) -> str:
        return self._model_name or "unknown"

    def _ensure_loaded(self) -> None:
        if self._generator is not None:
            return

        # Lazy imports: keep placeholder mode usable without installing TF/Magenta.
        import magenta.music as mm  # type: ignore[import-not-found]
        from magenta.models.performance_rnn import performance_sequence_generator  # type: ignore[import-not-found]
        from magenta.protobuf import generator_pb2  # type: ignore[import-not-found]
        from magenta.protobuf import music_pb2  # type: ignore[import-not-found]

        t0 = time.perf_counter()
        bundle_file, model_name = self._resolve_bundle_and_model_name()

        bundle = mm.sequence_generator_bundle.read_bundle_file(bundle_file)
        generator_map = performance_sequence_generator.get_generator_map()
        generator_factory = generator_map[model_name]
        generator = generator_factory(checkpoint=None, bundle=bundle)
        generator.initialize()

        self._music_pb2 = music_pb2
        self._generator_pb2 = generator_pb2
        self._bundle_file = bundle_file
        self._model_name = model_name
        self._generator = generator
        self._load_ms = int((time.perf_counter() - t0) * 1000)

        print(f"[Magenta] loaded model={model_name} bundle={bundle_file} load_ms={self._load_ms}")

    def _resolve_bundle_and_model_name(self) -> tuple[str, str]:
        explicit_bundle = os.environ.get("DUET_BUNDLE_FILE")
        explicit_model_name = os.environ.get("DUET_MODEL_NAME")
        if explicit_bundle:
            bundle_file = os.path.abspath(explicit_bundle)
            if explicit_model_name:
                return (bundle_file, explicit_model_name)
            basename = os.path.basename(bundle_file)
            return (bundle_file, self._infer_model_name_from_bundle_basename(basename))

        models_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "models"))
        candidates: list[tuple[str, str]] = [
            ("performance_with_dynamics_and_modkey.mag", "performance_with_dynamics_and_modkey"),
            ("performance_with_dynamics.mag", "performance_with_dynamics"),
        ]
        for filename, model_name in candidates:
            path = os.path.join(models_dir, filename)
            if os.path.exists(path):
                return (os.path.abspath(path), model_name)

        raise FileNotFoundError(
            "Magenta bundle (.mag) not found.\n"
            "Run: ./python_backend/scripts/download_duet_model.sh\n"
            "Or set DUET_BUNDLE_FILE=/path/to/bundle.mag"
        )

    def _infer_model_name_from_bundle_basename(self, basename: str) -> str:
        lowered = basename.lower()
        if "and_modkey" in lowered:
            return "performance_with_dynamics_and_modkey"
        if "performance_with_dynamics" in lowered:
            return "performance_with_dynamics"
        return "performance_with_dynamics"

    def generate_response(
        self,
        notes: list[DialogueNote],
        params: GenerateParams,
        session_id: str | None,
    ) -> list[DialogueNote]:
        # NOTE: Generator is not guaranteed thread-safe. Serialize generation.
        del session_id

        self._ensure_loaded()

        prompt_end_sec = 0.0
        for note in notes:
            prompt_end_sec = max(prompt_end_sec, float(note.time) + float(note.duration))

        primer_sequence = dialogue_notes_to_note_sequence(notes, qpm=120.0)

        reply_len_sec = self._reply_len_sec_from_max_tokens(int(params.max_tokens))
        start_time = prompt_end_sec
        end_time = prompt_end_sec + reply_len_sec

        with self._lock:
            generator_options = self._generator_pb2.GeneratorOptions()
            generator_options.args["temperature"].float_value = self._temperature_from_top_p(float(params.top_p))
            generator_options.generate_sections.add(start_time=float(start_time), end_time=float(end_time))
            sequence = self._generator.generate(primer_sequence, generator_options)

        reply = note_sequence_to_dialogue_notes(sequence, start_at_sec=float(prompt_end_sec))
        reply = self._postprocess_reply_notes(reply, prompt_notes=notes)
        return legalize_notes(reply)

    def _reply_len_sec_from_max_tokens(self, max_tokens: int) -> float:
        # Keep behavior consistent with the local rule backend.
        seconds = float(max_tokens) / 64.0
        return max(2.0, min(12.0, seconds))

    def _temperature_from_top_p(self, top_p: float) -> float:
        # Performance RNN doesn't have `top_p`; we map it to `temperature`.
        # More top_p -> more randomness (higher temperature).
        top_p = max(0.0, min(1.0, float(top_p)))
        t = 0.0
        if top_p <= 0.7:
            t = 0.0
        elif top_p >= 1.0:
            t = 1.0
        else:
            t = (top_p - 0.7) / 0.3
        temperature = 0.8 + (1.2 - 0.8) * t
        return max(0.5, min(1.5, temperature))

    def _postprocess_reply_notes(self, reply_notes: list[DialogueNote], prompt_notes: list[DialogueNote]) -> list[DialogueNote]:
        # Clamp to a piano-friendly range and avoid extreme values.
        default_velocity = 80
        if prompt_notes:
            velocities = [int(n.velocity) for n in prompt_notes if int(n.velocity) > 0]
            if velocities:
                default_velocity = int(sum(velocities) / len(velocities))
                default_velocity = max(1, min(127, default_velocity))

        processed: list[DialogueNote] = []
        for n in reply_notes:
            duration = float(n.duration)
            if duration < 0.03:
                continue
            processed.append(
                DialogueNote(
                    note=max(21, min(108, int(n.note))),
                    velocity=max(1, min(127, int(n.velocity) if int(n.velocity) > 0 else default_velocity)),
                    time=float(n.time),
                    duration=duration,
                )
            )

        return processed
