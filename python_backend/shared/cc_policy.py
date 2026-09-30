from __future__ import annotations

from dataclasses import dataclass

from shared.aria_protocol import ControlChangeEvent, ImprovEvent, ordered_events


@dataclass(frozen=True)
class DefaultCCPolicy:
    default_cc7: int | None = 100
    default_cc11: int | None = 100

    def __post_init__(self) -> None:
        for name, value in (("default_cc7", self.default_cc7), ("default_cc11", self.default_cc11)):
            if value is not None and (isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 127):
                raise ValueError(f"{name} must be None or an integer in 0...127")


def inject_defaults(events: list[ImprovEvent], *, policy: DefaultCCPolicy) -> list[ImprovEvent]:
    defaults: list[ImprovEvent] = []

    if policy.default_cc7 is not None and not any(
        isinstance(e, ControlChangeEvent) and e.controller == 7 for e in events
    ):
        defaults.append(ControlChangeEvent(controller=7, value=policy.default_cc7, time=0.0))

    if policy.default_cc11 is not None and not any(
        isinstance(e, ControlChangeEvent) and e.controller == 11 for e in events
    ):
        defaults.append(ControlChangeEvent(controller=11, value=policy.default_cc11, time=0.0))

    if not defaults:
        return events

    return ordered_events(defaults + events)

