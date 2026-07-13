from __future__ import annotations

from dataclasses import dataclass

from shared.protocol_v2 import ControlChangeEvent, ImprovEvent, legalize_events


@dataclass(frozen=True)
class DefaultCCPolicy:
    default_cc7: int | None = 100
    default_cc11: int | None = 100

    def sanitize(self) -> "DefaultCCPolicy":
        def sanitize_value(value: int | None) -> int | None:
            if value is None:
                return None
            return max(0, min(127, int(value)))

        return DefaultCCPolicy(
            default_cc7=sanitize_value(self.default_cc7),
            default_cc11=sanitize_value(self.default_cc11),
        )


def inject_defaults(events: list[ImprovEvent], *, policy: DefaultCCPolicy) -> list[ImprovEvent]:
    policy = policy.sanitize()
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

    return legalize_events(defaults + events)

