"""Stateless spherical-Earth propagation from supplied speed and true bearing."""

from dataclasses import dataclass
from math import asin, atan2, cos, degrees, isfinite, radians, sin

EARTH_RADIUS_M = 6371000.0


def _finite_float(value: object, name: str) -> float:
    if type(value) not in (int, float):
        raise ValueError(f"{name} must be a finite int or float")
    try:
        result = float(value)
    except OverflowError as exc:
        raise ValueError(f"{name} exceeds floating-point range") from exc
    if not isfinite(result):
        raise ValueError(f"{name} must be finite")
    return result


@dataclass(frozen=True)
class DeadReckoningResult:
    """Destination in decimal degrees and this step's traveled distance in meters."""

    latitude: float
    longitude: float
    distance_m: float


def propagate_position(
    latitude: float,
    longitude: float,
    speed_mps: float,
    heading_deg: float,
    elapsed_time_s: float,
) -> DeadReckoningResult:
    """Propagate along a spherical great circle with the supplied initial bearing.

    Heading is degrees clockwise from true north. All inputs are validated even
    for zero motion. Output longitude is [-180, 180); +180 becomes -180 even at
    rest. Invalid input or distance overflow raises ValueError.
    """
    latitude = _finite_float(latitude, "latitude")
    longitude = _finite_float(longitude, "longitude")
    speed_mps = _finite_float(speed_mps, "speed_mps")
    heading_deg = _finite_float(heading_deg, "heading_deg")
    elapsed_time_s = _finite_float(elapsed_time_s, "elapsed_time_s")
    if not -90 <= latitude <= 90:
        raise ValueError("latitude must be in [-90, 90]")
    if not -180 <= longitude <= 180:
        raise ValueError("longitude must be in [-180, 180]")
    if speed_mps < 0:
        raise ValueError("speed_mps must be nonnegative")
    if not 0 <= heading_deg < 360:
        raise ValueError("heading_deg must be in [0, 360)")
    if elapsed_time_s < 0:
        raise ValueError("elapsed_time_s must be nonnegative")

    distance = speed_mps * elapsed_time_s
    if not isfinite(distance):
        raise ValueError("speed_mps * elapsed_time_s exceeds floating-point range")
    if distance == 0:
        return DeadReckoningResult(latitude, -180.0 if longitude == 180 else longitude, distance)

    lat1, lon1, bearing = radians(latitude), radians(longitude), radians(heading_deg)
    angular_distance = distance / EARTH_RADIUS_M
    sin_lat2 = (sin(lat1) * cos(angular_distance)
                + cos(lat1) * sin(angular_distance) * cos(bearing))
    # Protect asin against roundoff in a mathematically bounded intermediate;
    # public inputs are rejected, never clamped.
    lat2 = asin(max(-1.0, min(1.0, sin_lat2)))
    lon2 = lon1 + atan2(
        sin(bearing) * sin(angular_distance) * cos(lat1),
        cos(angular_distance) - sin(lat1) * sin(lat2),
    )
    return DeadReckoningResult(degrees(lat2), (degrees(lon2) + 180) % 360 - 180, distance)
