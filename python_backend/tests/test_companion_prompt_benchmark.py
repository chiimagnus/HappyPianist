from __future__ import annotations

import sys
import unittest
from pathlib import Path

PYTHON_BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(PYTHON_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(PYTHON_BACKEND_ROOT))
SCRIPTS_ROOT = PYTHON_BACKEND_ROOT / "scripts"
if str(SCRIPTS_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_ROOT))

from companion_e2e_acceptance import (
    ParsedMIDI,
    ParsedNote,
    Scenario,
    decision_payload,
    sample_scenarios,
)
from shared.companion_prompt_profiles import (
    action_from_semantics,
    action_mapping_metadata,
    profile_names,
    semantic_peak_probabilities,
    semantic_scores,
)


def semantic_values(**overrides: float) -> dict[str, float]:
    values = {
        "continuing": 0.5,
        "finished": 0.5,
        "space": 0.5,
        "reasserted": 0.5,
    }
    values.update(overrides)
    return values


class CompanionPromptBenchmarkTests(unittest.TestCase):
    def test_action_mapping_is_deterministic_and_prioritized(self) -> None:
        base_state = {"is_ai_playback_active": False, "recent_note_density_per_second": 1.0}

        self.assertEqual(
            action_from_semantics(
                {**base_state, "is_ai_playback_active": True},
                semantic_values(
                    continuing=0.9, finished=0.9, space=0.9, reasserted=0.55
                ),
            ),
            "yield",
        )
        self.assertEqual(
            action_from_semantics(
                base_state, semantic_values(continuing=0.4, finished=0.55)
            ),
            "respond",
        )
        self.assertEqual(
            action_from_semantics(
                base_state, semantic_values(continuing=0.9, finished=0.1, space=0.4)
            ),
            "listen",
        )
        self.assertEqual(
            action_from_semantics(
                base_state, semantic_values(continuing=0.9, finished=0.1, space=0.9)
            ),
            "support",
        )
        self.assertEqual(
            action_from_semantics(
                {**base_state, "recent_note_density_per_second": 2.0},
                semantic_values(continuing=0.9, finished=0.1, space=0.9),
            ),
            "sparse",
        )
        self.assertEqual(
            action_mapping_metadata(),
            {
                "id": "semantic-v1",
                "semantic_threshold": 0.55,
                "sparse_density_threshold": 2.0,
                "priority": ["yield", "respond", "listen", "support_or_sparse"],
            },
        )

    def test_semantic_response_validation_preserves_noul_and_distribution_confidence(
        self,
    ) -> None:
        probabilities = {str(value): 1.0 / 9.0 for value in range(1, 10)}
        response = {
            "answers": {
                key: {
                    "type": "noul",
                    "noul": 0.5,
                    "rating": {"probabilities": probabilities},
                }
                for key in ("continuing", "finished", "space", "reasserted")
            }
        }

        self.assertEqual(
            semantic_scores(response),
            {
                "continuing": 0.5,
                "finished": 0.5,
                "space": 0.5,
                "reasserted": 0.5,
            },
        )
        peaks = semantic_peak_probabilities(response)
        self.assertEqual(
            set(peaks), {"continuing", "finished", "space", "reasserted"}
        )
        for value in peaks.values():
            self.assertAlmostEqual(value, 1.0 / 9.0)

        invalid = {"answers": dict(response["answers"])}
        invalid["answers"].pop("space")
        with self.assertRaisesRegex(ValueError, "expected semantic answers"):
            semantic_scores(invalid)

    def test_sampling_is_fixed_stratified_and_fails_when_a_stratum_is_short(
        self,
    ) -> None:
        states = {"active_dense", "takeover_overlay"}
        candidates = []
        for source in ("maestro", "pop909"):
            for state in sorted(states):
                for index in range(3):
                    candidates.append(
                        {
                            "source": source,
                            "state": state,
                            "file": f"{source}-{state}-{index}.mid",
                            "timestamp": float(index + 1),
                            "provenance": (
                                "synthetic_ai_playback_overlay_on_natural_user_midi"
                                if state == "takeover_overlay"
                                else "natural_midi"
                            ),
                        }
                    )
        corpus = {
            "files": {"maestro": 1, "pop909": 1},
            "candidates": candidates,
        }

        first = sample_scenarios(
            corpus, states=states, cases_per_state_per_source=2, seed=7
        )
        second = sample_scenarios(
            corpus, states=states, cases_per_state_per_source=2, seed=7
        )
        self.assertEqual(
            [scenario.case_id for scenario in first],
            [scenario.case_id for scenario in second],
        )
        self.assertEqual(len(first), 8)
        self.assertEqual(sum(scenario.ai_playback_active for scenario in first), 4)

        with self.assertRaisesRegex(RuntimeError, "insufficient candidates"):
            sample_scenarios(
                corpus, states=states, cases_per_state_per_source=4, seed=7
            )

    def test_last_user_event_includes_a_recent_note_on(self) -> None:
        parsed = ParsedMIDI(
            notes=[ParsedNote(note=60, velocity=90, start=9.9, duration=1.0)],
            ccs=[],
            duration=11.0,
        )
        scenario = Scenario(
            source="maestro",
            file="test.mid",
            name="active_dense",
            cutoff=10.0,
            provenance="natural_midi",
            ai_playback_active=False,
        )

        payload = decision_payload(parsed, scenario, prompt_window=3.0)
        self.assertAlmostEqual(payload["seconds_since_last_user_event"], 0.1)
        self.assertAlmostEqual(payload["seconds_since_last_note_on"], 0.1)
        self.assertEqual(payload["held_notes_count"], 1)

    def test_prompt_profiles_cover_the_planned_distinct_experiment_families(
        self,
    ) -> None:
        self.assertEqual(
            profile_names(),
            (
                "direct",
                "observable",
                "observable_thresholds",
                "observable_examples",
                "conservative",
            ),
        )


if __name__ == "__main__":
    unittest.main()
