import pytest

from shared.cc_policy import DefaultCCPolicy, inject_defaults
from shared.aria_protocol import ControlChangeEvent


def test_zero_is_a_valid_default_control_change_value() -> None:
    events = inject_defaults(
        [],
        policy=DefaultCCPolicy(default_cc7=0, default_cc11=0),
    )

    assert events == [
        ControlChangeEvent(controller=7, value=0, time=0.0),
        ControlChangeEvent(controller=11, value=0, time=0.0),
    ]


def test_invalid_default_control_change_value_is_rejected() -> None:
    with pytest.raises(ValueError):
        DefaultCCPolicy(default_cc7=128)
