from __future__ import annotations

import statistics
from typing import Any


SEMANTIC_KEYS = ("continuing", "finished", "space", "reasserted")
ACTION_THRESHOLD = 0.55
SPARSE_DENSITY_THRESHOLD = 2.0
ACTION_MAPPING_ID = "semantic-v1"


SEMANTIC_PROMPT_PROFILES: dict[str, dict[str, str]] = {
    "direct": {
        "continuing": (
            "根据当前钢琴状态，用户是否仍在继续当前演奏过程，尚未明确结束？"
        ),
        "finished": (
            "根据当前钢琴状态，是否有充分证据表明用户已经完成当前乐句，并留出了让 AI 回应的空间？"
        ),
        "space": (
            "在用户仍继续演奏的前提下，当前织体是否留有足够空间，让 AI 可以轻量加入伴奏而不抢主导？"
        ),
        "reasserted": (
            "如果 AI 当前正在演奏，用户是否已经重新明显进入并夺回演奏主导，因此 AI 应该让位？"
        ),
    },
    "observable": {
        "continuing": (
            "只根据可观测 MIDI 状态判断：当前是否仍有近期按键、按住音符、连续 onset 或踏板保持等证据，"
            "支持把用户视为仍在继续当前演奏，而不是已经结束？"
        ),
        "finished": (
            "只根据可观测 MIDI 状态判断：是否同时缺少近期继续演奏迹象、没有按住音符、踏板已抬起，"
            "并且停顿足够明确，支持判断当前乐句已经结束？"
        ),
        "space": (
            "只根据可观测 MIDI 状态判断：用户仍在演奏时，当前音符密度和时序是否足够疏朗稳定，"
            "使 AI 加入轻量伴奏不会拥挤或抢主导？"
        ),
        "reasserted": (
            "只根据可观测 MIDI 状态判断：在 AI 正在演奏的情况下，用户是否出现了近期、持续或高密度的主动演奏，"
            "足以说明用户重新主导，AI 应立即让位？若 AI 没有演奏，应否定。"
        ),
    },
    "observable_thresholds": {
        "continuing": (
            "只根据可观测 MIDI 判断用户是否仍在继续。近期仍有按键/按住音符，或踏板保持中的短停顿，支持‘继续’；"
            "若没有按住音符、踏板已抬起且距最后按键已明显超过普通演奏间隔，则不支持‘继续’。"
        ),
        "finished": (
            "只根据可观测 MIDI 判断乐句是否已经明确结束。没有按住音符、踏板抬起、距最后按键和最后事件都已形成明显停顿，"
            "共同支持‘结束’；近期仍有按键、持续 onset 或踏板保持则不支持。"
        ),
        "space": (
            "判断用户仍在演奏时是否有伴奏空间。低到中等音符密度、较长音符间隔或持续音支持‘有空间’；"
            "快速高密度连续演奏不支持。用户已经完全停止时不要把静默误当成伴奏空间。"
        ),
        "reasserted": (
            "判断用户是否在 AI 演奏期间重新夺回主导。AI 正在演奏且用户出现非常近期、持续或高密度的主动按键，支持‘重新接管’；"
            "AI 没有演奏时必须否定。"
        ),
    },
    "observable_examples": {
        "continuing": (
            "判断用户是否仍在继续当前演奏。例：最后按键刚发生、onset 连续或踏板保持中的短停顿→是；"
            "无按住音符、踏板抬起并已经明显停了一段时间→否。"
        ),
        "finished": (
            "判断用户是否已经明确结束当前乐句。例：无按住音符+踏板抬起+明显停顿→是；"
            "刚按过键、onset 仍连续或踏板仍保持→否。不要把普通呼吸停顿当结束。"
        ),
        "space": (
            "判断用户继续演奏时是否有轻量伴奏空间。例：音符稀疏、间隔较长、织体留白→是；"
            "快速高密度连续演奏→否；用户已完全停止也不是‘伴奏空间’。"
        ),
        "reasserted": (
            "判断用户是否在 AI 正在演奏时重新主导。例：AI 正在演奏+用户突然密集连续进入→是；"
            "AI 没有演奏→否。"
        ),
    },
    "conservative": {
        "continuing": (
            "判断用户是否仍在当前演奏过程中。只要近期仍有明显演奏活动、按住音符或踏板保持中的短暂停顿，"
            "就倾向于仍在继续；只有有充分结束证据才否定。"
        ),
        "finished": (
            "判断用户是否已经明确结束当前乐句。要求有强结束证据：没有按住音符、踏板抬起、"
            "近期没有继续按键；普通短暂停顿或踏板保持不能算结束。"
        ),
        "space": (
            "判断是否有明确伴奏空间。只有用户仍在演奏且织体不拥挤、节奏留白明显时才肯定；"
            "高密度连续演奏或用户已经停止时都否定。"
        ),
        "reasserted": (
            "判断用户是否在 AI 演奏期间重新夺回主导。只有 AI 正在演奏且用户出现明显持续/高密度主动演奏时才肯定；"
            "AI 未在演奏时必须否定。"
        ),
    },
}


def profile_names() -> tuple[str, ...]:
    return tuple(SEMANTIC_PROMPT_PROFILES)


def semantic_questions(profile: str) -> dict[str, dict[str, Any]]:
    try:
        instructions = SEMANTIC_PROMPT_PROFILES[profile]
    except KeyError as exc:
        raise ValueError(f"unknown prompt profile: {profile}") from exc

    return {
        question_id: {
            "type": "noul",
            "instructions": prompt,
            "criteria": {
                "true": "当前状态支持这个判断。",
                "false": "当前状态不支持这个判断。",
            },
        }
        for question_id, prompt in instructions.items()
    }


def format_companion_state(state: dict[str, Any]) -> str:
    sustain = int(state.get("sustain_value", 0))
    notes = state.get("recent_notes", [])
    rendered_notes = ", ".join(
        (
            f"{int(note['midi'])}(力度={int(note['velocity'])},"
            f"距今={float(note['onset_seconds_ago']):.3f}秒,"
            f"时值={float(note['duration_seconds']):.3f}秒)"
        )
        for note in notes
    ) or "无"

    def seconds(value: Any) -> str:
        return "无" if value is None else f"{float(value):.3f}秒"

    ioi = state.get("recent_ioi_median_seconds")
    pitch_center = state.get("active_pitch_center")
    return "\n".join(
        [
            "当前钢琴交互状态：",
            f"当前按住音符数={int(state.get('held_notes_count', 0))}",
            f"延音踏板={sustain}（{'按下' if sustain >= 64 else '抬起'}）",
            f"最近音符间隔中位数={'无' if ioi is None else f'{float(ioi):.3f}秒'}",
            f"最近1秒音符密度={float(state.get('recent_note_density_per_second', 0.0)):.3f}音/秒",
            f"近期力度趋势={float(state.get('recent_velocity_trend', 0.0)):.3f}",
            f"距最后用户事件={seconds(state.get('seconds_since_last_user_event'))}",
            f"距最后一次按键={seconds(state.get('seconds_since_last_note_on'))}",
            f"当前音高中心={'无' if pitch_center is None else f'{float(pitch_center):.3f}'}",
            f"AI当前正在演奏={'是' if state.get('is_ai_playback_active') else '否'}",
            f"最近音符={rendered_notes}",
        ]
    )


def classifier_payload(
    *,
    model: str,
    state: dict[str, Any] | str,
    profile: str,
) -> dict[str, Any]:
    rendered_state = format_companion_state(state) if isinstance(state, dict) else state
    return {
        "model": model,
        "state": rendered_state,
        "questions": semantic_questions(profile),
    }


def _semantic_answers(response: dict[str, Any]) -> dict[str, dict[str, Any]]:
    answers = response.get("answers")
    if not isinstance(answers, dict) or set(answers) != set(SEMANTIC_KEYS):
        raise ValueError("classifier response does not contain the expected semantic answers")
    for question_id in SEMANTIC_KEYS:
        answer = answers[question_id]
        if not isinstance(answer, dict) or answer.get("type") != "noul":
            raise ValueError(f"semantic answer {question_id!r} is not a Noul answer")
        value = float(answer["noul"])
        if not 0.1 <= value <= 0.9:
            raise ValueError(f"semantic answer {question_id!r} is outside 0.1...0.9")
    return answers


def semantic_scores(response: dict[str, Any]) -> dict[str, float]:
    answers = _semantic_answers(response)
    return {question_id: float(answers[question_id]["noul"]) for question_id in SEMANTIC_KEYS}


def semantic_peak_probabilities(response: dict[str, Any]) -> dict[str, float]:
    answers = _semantic_answers(response)
    result: dict[str, float] = {}
    for question_id in SEMANTIC_KEYS:
        probabilities = answers[question_id].get("rating", {}).get("probabilities")
        if not isinstance(probabilities, dict) or set(probabilities) != set("123456789"):
            raise ValueError(f"semantic answer {question_id!r} has an invalid probability distribution")
        values = [float(probabilities[label]) for label in "123456789"]
        if any(value < 0 or value > 1 for value in values) or abs(sum(values) - 1.0) > 1e-4:
            raise ValueError(f"semantic answer {question_id!r} has invalid probabilities")
        result[question_id] = max(values)
    return result


def action_mapping_metadata() -> dict[str, Any]:
    return {
        "id": ACTION_MAPPING_ID,
        "semantic_threshold": ACTION_THRESHOLD,
        "sparse_density_threshold": SPARSE_DENSITY_THRESHOLD,
        "priority": ["yield", "respond", "listen", "support_or_sparse"],
    }


def action_from_semantics(
    state: dict[str, Any],
    scores: dict[str, float],
    *,
    threshold: float = ACTION_THRESHOLD,
) -> str:
    continuing = scores["continuing"]
    finished = scores["finished"]
    space = scores["space"]
    reasserted = scores["reasserted"]

    if bool(state.get("is_ai_playback_active")) and reasserted >= threshold:
        return "yield"

    if finished >= threshold and continuing < threshold:
        return "respond"

    if continuing < threshold:
        return "listen"

    if space < threshold:
        return "listen"

    density = float(state.get("recent_note_density_per_second", 0.0))
    return "sparse" if density >= SPARSE_DENSITY_THRESHOLD else "support"


def median_semantic_scores(cases: list[dict[str, Any]]) -> dict[str, float]:
    return {
        key: statistics.median(float(case["semantic_scores"][key]) for case in cases)
        for key in SEMANTIC_KEYS
    }


def median_semantic_peak_probabilities(cases: list[dict[str, Any]]) -> dict[str, float]:
    return {
        key: statistics.median(
            float(case["semantic_peak_probabilities"][key]) for case in cases
        )
        for key in SEMANTIC_KEYS
    }
