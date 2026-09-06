"""Direct GNSS/DR source selection; detection and propagation remain separate."""

from dataclasses import dataclass
from math import isfinite
from typing import Literal

from navigation_engine.dead_reckoning.dead_reckoning import propagate_position
from navigation_engine.gnss.gnss_availability import GNSSStatus

NavigationMode = Literal["GNSS_INS", "DEAD_RECKONING"]


@dataclass(frozen=True)
class NavigationModeResult:
    """Last successful position and mode; a local result, not NavigationOutput."""

    latitude: float
    longitude: float
    navigation_mode: NavigationMode
    gnss_status: GNSSStatus


def _coordinate(value: object, name: str, limit: float) -> float:
    if type(value) not in (int, float):
        raise ValueError(f"{name} must be a finite int or float")
    try:
        number = float(value)
    except OverflowError as exc:
        raise ValueError(f"{name} exceeds floating-point range") from exc
    if not isfinite(number) or not -limit <= number <= limit:
        raise ValueError(f"{name} must be finite and in [-{limit}, {limit}]")
    return number


class NavigationModeController:
    """Remember one position; commit state only after an update succeeds."""

    def __init__(self) -> None:
        self._state: NavigationModeResult | None = None

    @property
    def state(self) -> NavigationModeResult | None:
        """Last successful immutable result, or None before initialization."""
        return self._state

    @property
    def initialized(self) -> bool:
        """Whether a valid GNSS position has initialized this controller."""
        return self._state is not None

    def update(
        self,
        gnss_status: GNSSStatus,
        gnss_latitude: float | None = None,
        gnss_longitude: float | None = None,
        speed_mps: float | None = None,
        heading_deg: float | None = None,
        elapsed_time_s: float | None = None,
    ) -> NavigationModeResult:
        """Use GNSS directly when AVAILABLE; otherwise propagate the last position.

        Pass Issue #9 result.status and coordinates from its associated fix.
        AVAILABLE ignores DR arguments. UNAVAILABLE ignores GNSS coordinates.
        Invalid active-branch inputs or uninitialized DR raise ValueError.
        """
        if type(gnss_status) is not str or gnss_status not in ("AVAILABLE", "UNAVAILABLE"):
            raise ValueError("gnss_status must be AVAILABLE or UNAVAILABLE")
        if gnss_status == "AVAILABLE":
            latitude = _coordinate(gnss_latitude, "gnss_latitude", 90)
            longitude = _coordinate(gnss_longitude, "gnss_longitude", 180)
            result = NavigationModeResult(latitude, longitude, "GNSS_INS", "AVAILABLE")
        else:
            if self._state is None:
                raise ValueError("Navigation is not initialized: a valid GNSS position is required")
            position = propagate_position(
                self._state.latitude, self._state.longitude,
                speed_mps, heading_deg, elapsed_time_s,
            )
            result = NavigationModeResult(
                position.latitude, position.longitude, "DEAD_RECKONING", "UNAVAILABLE",
            )
        self._state = result
        return result
